# Production Deployment: GA Read-Only Mode Fix

## What Changed

The GA Friendliness service now supports read-only mode, which:
- ✅ Prevents accidental database corruption from the web server
- ✅ Eliminates permission errors (no WAL mode, no schema writes)
- ✅ Makes it explicit that web API only reads, never writes
- ✅ Slightly faster startup (no schema checks)

## Deployment Steps

### Step 1: Update Code on Production

```bash
# SSH to production server
ssh ro-z.net

# Navigate to project
cd /var/www/flyfun-apps

# Pull latest changes
git pull origin main
```

### Step 2: Update Production Environment File

Edit `/var/www/flyfun-apps/web/server/prod.env` and add:

```bash
# GA Friendliness Configuration
GA_META_DB=/var/www/flyfun-apps/tmp/ga_meta.sqlite
GA_META_READONLY=true  # Read-only mode for web API (prevents writes)
```

**Note**: Make sure the path to `GA_META_DB` is correct for your setup.

### Step 3: Restart the Service

```bash
sudo systemctl restart euro-aip.service
```

### Step 4: Verify It Works

```bash
# Check service status
sudo systemctl status euro-aip.service

# Check logs for the new initialization message
sudo journalctl -u euro-aip.service -f

# You should see:
# "GA Friendliness service initialized (readonly=True): /path/to/ga_meta.sqlite"
```

### Step 5: Test API Endpoints

```bash
# Test GA config endpoint
curl https://maps.flyfun.aero/api/ga/config

# Test GA summary endpoint
curl https://maps.flyfun.aero/api/ga/summary/LFMD
```

## What If It Still Fails?

If you still get permission errors, it might be because:

1. **WAL files exist from before**: Delete them
   ```bash
   sudo rm /var/www/flyfun-apps/tmp/ga_meta.sqlite-wal
   sudo rm /var/www/flyfun-apps/tmp/ga_meta.sqlite-shm
   ```

2. **Database doesn't exist**: Check the path
   ```bash
   ls -la /var/www/flyfun-apps/tmp/ga_meta.sqlite
   ```

3. **Database is truly read-only (filesystem level)**: Make it readable
   ```bash
   sudo chmod 644 /var/www/flyfun-apps/tmp/ga_meta.sqlite
   sudo chown www-data:www-data /var/www/flyfun-apps/tmp/ga_meta.sqlite
   ```

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `GA_META_DB` | None | Path to `ga_meta.sqlite` database |
| `GA_META_READONLY` | `true` | Open database in read-only mode |

**For Web Server (Production)**: Always use `GA_META_READONLY=true`
**For Build Tools (Local)**: Set `GA_META_READONLY=false` to allow writes

## Benefits

### Before (WAL Mode)
- Opens database in write mode
- Enables WAL journaling (creates `-wal` and `-shm` files)
- Runs schema version checks (may INSERT/UPDATE)
- Requires write permissions on directory
- ❌ Error: "attempt to write a readonly database"

### After (Read-Only Mode)
- Opens database with `mode=ro` URI flag
- Sets `PRAGMA query_only = ON` for safety
- Skips all schema checks
- Only needs read permission on database file
- ✅ Works perfectly for production web API

## Rollback

If you need to rollback for any reason:

1. Remove `GA_META_READONLY=true` from `prod.env`
2. Fix file permissions (the old way)
3. Restart service

But honestly, read-only mode is better! 😊

