# Migration Guide: ALLOWED_DIR → ALLOWED_DIRS

## What Changed

**Before:**
```python
ALLOWED_DIR = "./"  # Single directory
```

**After:**
```python
ALLOWED_DIRS = [    # Multiple directories
    "./",
    "/var/www/flyfun-apps/data",
    "/var/www/flyfun-apps/tmp",
]
```

## Why This Change?

You can now have databases and config files in different directories:
- `airports.db` in `/var/www/flyfun-apps/data/`
- `ga_meta.sqlite` in `/var/www/flyfun-apps/tmp/`
- `rules.json` in `/var/www/flyfun-apps/config/`

All secured with path validation in production!

## Production Deployment

### Step 1: Update security_config.py

Edit `/var/www/flyfun-apps/web/server/security_config.py`:

```python
# OLD (remove this):
ALLOWED_DIR = "./"

# NEW (add this):
ALLOWED_DIRS = [
    "./",
    "/var/www/flyfun-apps/data",
    "/var/www/flyfun-apps/tmp",
    # Add any other directories where you store databases/config
]
```

### Step 2: Git Pull

```bash
cd /var/www/flyfun-apps
git pull  # Gets updated config_helpers.py with new logic
```

### Step 3: Verify Configuration

```bash
cd /var/www/flyfun-apps/web/server
python3 -c "
import sys
sys.path.insert(0, '../../')
from config_helpers import _is_path_allowed, get_safe_db_path, get_safe_ga_meta_db_path
from security_config import ALLOWED_DIRS, ENVIRONMENT

print(f'Environment: {ENVIRONMENT}')
print(f'Allowed Directories: {ALLOWED_DIRS}')
print(f'\\nPath Tests:')
print(f'  airports.db path: {get_safe_db_path()}')
print(f'  ga_meta.sqlite path: {get_safe_ga_meta_db_path()}')
"
```

### Step 4: Restart Service

```bash
sudo systemctl restart euro-aip.service
```

### Step 5: Verify It Works

```bash
# Check logs
sudo journalctl -u euro-aip.service -n 50

# Should see successful startup messages
```

## Example Production Configuration

Here's a typical production `security_config.py` setup:

```python
# Environment Configuration
ENVIRONMENT = os.getenv("ENVIRONMENT", "production")
FORCE_HTTPS = True

# Directory Security
# Multiple directories for different purposes
ALLOWED_DIRS = [
    "/var/www/flyfun-apps",           # Base directory
    "/var/www/flyfun-apps/data",      # Main databases
    "/var/www/flyfun-apps/tmp",       # Temporary/cache databases
    "/var/www/flyfun-apps/config",    # Config files
]

# CORS Configuration
ALLOWED_ORIGINS = [
    "https://maps.flyfun.aero",
    "https://flyfun.aero",
]

# ... rest of config ...
```

## How It Works

### Development Mode (ENVIRONMENT=development)
- **All paths allowed** for convenience
- No path validation applied
- Great for local development

### Production Mode (ENVIRONMENT=production)
- **Only paths in ALLOWED_DIRS are accepted**
- Security validation on all database paths
- Invalid paths are rejected or moved to first allowed directory

### Path Validation Logic

```python
def _is_path_allowed(path: str) -> bool:
    """Check if a path starts with any allowed directory."""
    if ENVIRONMENT != "production":
        return True  # All paths allowed in dev
    
    # In production, check each allowed directory
    for allowed_dir in ALLOWED_DIRS:
        if path.startswith(allowed_dir):
            return True  # Path is in allowed directory
    
    return False  # Path not allowed
```

## Examples

### Valid Production Paths

✅ `/var/www/flyfun-apps/data/airports.db`
✅ `/var/www/flyfun-apps/tmp/ga_meta.sqlite`
✅ `./rules.json` (if "./" is in ALLOWED_DIRS)

### Invalid Production Paths (Blocked)

❌ `/etc/passwd`
❌ `/tmp/malicious.db`
❌ `../../../etc/shadow`
❌ `/home/user/data.db` (unless explicitly allowed)

## Security Benefits

1. **Defense in Depth**: Even if env vars are compromised, paths are validated
2. **Flexible Configuration**: Different databases can live in different directories
3. **Clear Intent**: ALLOWED_DIRS explicitly lists trusted locations
4. **Production Safety**: Development convenience without production risk

## Troubleshooting

### Error: "Database path not allowed"

**Cause**: Path is not in ALLOWED_DIRS

**Solution**: Add the directory to ALLOWED_DIRS:
```python
ALLOWED_DIRS = [
    "./",
    "/path/to/your/database/directory",  # Add this
]
```

### Database not found after update

**Cause**: Path validation moved file to fallback directory

**Solution**: 
1. Check where file ended up: `find /var/www/flyfun-apps -name "*.db"`
2. Either move file to allowed directory OR add current directory to ALLOWED_DIRS

## Rollback

If you need to rollback:

1. In production `security_config.py`, change back:
   ```python
   ALLOWED_DIR = "./"  # Old single directory
   ```

2. Git checkout old version of `config_helpers.py`:
   ```bash
   git checkout HEAD~1 web/server/config_helpers.py
   ```

3. Restart service

But honestly, the new multi-directory approach is more flexible! 🎯

