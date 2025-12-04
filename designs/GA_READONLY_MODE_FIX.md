# GA Friendliness Read-Only Database Fix

## Problem

Production server error:
```
Dec 02 21:20:06 ro-z.net start_server.zsh[2856656]: 2025-12-02 21:20:06,165 - api.ga_friendliness - ERROR - Failed to initialize GA Friendliness service: attempt to write a readonly database
```

## Root Cause

The GA Friendliness service initialization (`GAMetaStorage.__init__`) calls `get_connection(db_path)` which:

1. **Sets WAL mode**: `PRAGMA journal_mode=WAL` - Creates `-wal` and `-shm` files (requires write access)
2. **Runs schema version check**: `ensure_schema_version()` - May INSERT/UPDATE metadata
3. **Creates parent directories**: `db_path.parent.mkdir()` - Requires write access

The production server runs as `www-data` user, but the database file/directory has incorrect permissions.

## Immediate Fix (Production)

### Check Current Permissions

```bash
# SSH to production server
ssh ro-z.net

# Find GA_META_DB location (check prod.env)
grep GA_META_DB /var/www/flyfun-apps/web/server/prod.env

# Check permissions
ls -la /var/www/flyfun-apps/tmp/ga_meta.sqlite
ls -la /var/www/flyfun-apps/tmp/
```

### Fix Permissions

```bash
# Assuming database is in /var/www/flyfun-apps/tmp/ga_meta.sqlite
sudo chown www-data:www-data /var/www/flyfun-apps/tmp/ga_meta.sqlite
sudo chown www-data:www-data /var/www/flyfun-apps/tmp
sudo chmod 664 /var/www/flyfun-apps/tmp/ga_meta.sqlite
sudo chmod 775 /var/www/flyfun-apps/tmp

# Also fix WAL files if they exist
sudo chown www-data:www-data /var/www/flyfun-apps/tmp/ga_meta.sqlite-wal 2>/dev/null || true
sudo chown www-data:www-data /var/www/flyfun-apps/tmp/ga_meta.sqlite-shm 2>/dev/null || true
sudo chmod 664 /var/www/flyfun-apps/tmp/ga_meta.sqlite-* 2>/dev/null || true

# Restart service
sudo systemctl restart euro-aip.service

# Verify
sudo systemctl status euro-aip.service
tail -f /tmp/flyfun-logs/web_server.log
```

## Long-Term Fix: Add Read-Only Mode

### Why Read-Only Mode?

For web servers that only **query** the GA database (no writes), we should support:
- Opening database in read-only mode
- Skipping WAL mode setup
- Skipping schema version checks that require writes
- Gracefully handling missing schema

### Implementation

#### 1. Add `readonly` Parameter to `get_connection`

**File**: `shared/ga_friendliness/database.py`

```python
def get_connection(db_path: Path, readonly: bool = False) -> sqlite3.Connection:
    """
    Get a connection to ga_meta.sqlite.
    
    Creates the database and schema if it doesn't exist (unless readonly=True).
    Ensures schema is at current version.
    
    Args:
        db_path: Path to the database file
        readonly: If True, open in read-only mode (no schema checks/writes)
        
    Returns:
        Connection with schema at current version.
    """
    if readonly:
        # Read-only mode: database must exist
        if not db_path.exists():
            raise StorageError(f"Database not found (readonly mode): {db_path}")
        
        # Open with URI for read-only mode
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        
        # Set read-only pragmas
        conn.execute("PRAGMA query_only = ON")
        
        # No schema checks in read-only mode
        return conn
    
    # Write mode (existing behavior)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout = 30000")
    ensure_schema_version(conn)
    
    return conn
```

#### 2. Update `GAMetaStorage.__init__`

**File**: `shared/ga_friendliness/storage.py`

```python
class GAMetaStorage(StorageInterface):
    """
    Handles all database operations for ga_meta.sqlite.
    """

    def __init__(self, db_path: Path, readonly: bool = False):
        """
        Initialize storage.
        
        Args:
            db_path: Path to database file
            readonly: If True, open in read-only mode (no writes)
        """
        self.db_path = db_path
        self.readonly = readonly
        self.conn = get_connection(db_path, readonly=readonly)
        self._lock = threading.Lock()
        self._in_transaction = False
    
    def _check_readonly(self):
        """Raise error if attempting write operation in readonly mode."""
        if self.readonly:
            raise StorageError("Cannot perform write operation in readonly mode")
    
    def write_airfield_stats(self, stats: AirportStats) -> None:
        """Insert or update a row in ga_airfield_stats."""
        self._check_readonly()
        # ... existing implementation ...
```

#### 3. Update Web API Service

**File**: `web/server/api/ga_friendliness.py`

```python
class GAFriendlinessService:
    """Service for GA friendliness data access."""
    
    def __init__(self, db_path: Optional[str] = None, readonly: bool = True):
        """
        Initialize the service.
        
        Args:
            db_path: Path to ga_meta.sqlite. If None, service is disabled.
            readonly: If True, open database in read-only mode (default for web API)
        """
        self.db_path = db_path
        self.storage: Optional[GAMetaStorage] = None
        self.persona_manager: Optional[PersonaManager] = None
        self._enabled = False
        
        if db_path and Path(db_path).exists():
            try:
                # Web API only reads, so use readonly mode
                self.storage = GAMetaStorage(Path(db_path), readonly=readonly)
                self.persona_manager = PersonaManager(get_default_personas())
                self._enabled = True
                logger.info(f"GA Friendliness service initialized (readonly={readonly}): {db_path}")
            except Exception as e:
                logger.error(f"Failed to initialize GA Friendliness service: {e}")
                self._enabled = False
        else:
            logger.info("GA Friendliness service disabled (no database configured)")
```

#### 4. Environment Variable Support

**File**: `web/server/security_config.py`

Add optional read-only flag:

```python
def get_ga_friendliness_readonly() -> bool:
    """Check if GA database should be opened in read-only mode."""
    return os.getenv("GA_META_READONLY", "true").lower() == "true"
```

**File**: `web/server/main.py`

```python
# Initialize GA friendliness service (optional)
ga_meta_db_path = get_safe_ga_meta_db_path()
ga_readonly = get_ga_friendliness_readonly()
ga_service = ga_friendliness.GAFriendlinessService(
    ga_meta_db_path, 
    readonly=ga_readonly
)
```

#### 5. Update Environment Files

**File**: `web/server/dev.env.sample`

```bash
# GA Friendliness Configuration
GA_META_DB=/path/to/ga_meta.sqlite
GA_META_READONLY=false  # Set to true in production for web API
```

**File**: `web/server/prod.env` (on production server)

```bash
GA_META_DB=/var/www/flyfun-apps/tmp/ga_meta.sqlite
GA_META_READONLY=true  # Read-only mode for web API
```

## Testing

### Test Read-Only Mode Locally

```bash
# Make database read-only
chmod 444 /path/to/ga_meta.sqlite

# Start server with GA_META_READONLY=true
cd web/server
source ../../venv/bin/activate
export GA_META_READONLY=true
python main.py

# Verify service starts without errors
# Check logs: should see "initialized (readonly=True)"
```

### Test Read Operations Work

```bash
# Test API endpoints
curl http://localhost:8000/api/ga/config
curl http://localhost:8000/api/ga/summary/LFMD
```

### Test Write Operations Fail Gracefully

```python
# In Python shell
from shared.ga_friendliness.storage import GAMetaStorage
from pathlib import Path

storage = GAMetaStorage(Path("ga_meta.sqlite"), readonly=True)

# This should raise StorageError
try:
    storage.write_airfield_stats(...)
except StorageError as e:
    print(f"Expected error: {e}")
```

## Deployment Checklist

- [ ] Implement readonly mode in `database.py`
- [ ] Update `GAMetaStorage` with readonly support
- [ ] Update `GAFriendlinessService` to use readonly=True by default
- [ ] Add environment variable support
- [ ] Test locally with read-only database
- [ ] Update production `prod.env` with `GA_META_READONLY=true`
- [ ] OR fix file permissions (immediate fix)
- [ ] Deploy and verify
- [ ] Monitor logs for errors

## Benefits of Read-Only Mode

1. **Security**: Web API can't accidentally modify database
2. **Performance**: No WAL overhead, no schema checks on startup
3. **Flexibility**: Database can be on read-only filesystem or shared across instances
4. **Explicit Intent**: Makes it clear that web API is read-only

## Migration Path

### Phase 1: Immediate Fix (Today)
- Fix file permissions on production server
- Restart service
- Verify it works

### Phase 2: Add Read-Only Mode (This Week)
- Implement readonly parameter
- Test locally
- Deploy to production with `GA_META_READONLY=true`

### Phase 3: Document Pattern (Later)
- Update all design docs
- Add to production deployment guide
- Use same pattern for other read-only database access

