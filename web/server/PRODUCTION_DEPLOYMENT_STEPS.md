# Production Deployment: Complete Checklist

This guide covers deploying all recent changes to production in one go.

## Recent Changes

1. ✅ GA Friendliness read-only mode (prevents database write errors)
2. ✅ Config separation (security_config.py vs config_helpers.py)
3. ✅ Multiple allowed directories (ALLOWED_DIR → ALLOWED_DIRS)

## Pre-Deployment Checklist

- [ ] SSH access to production server
- [ ] Sudo privileges for systemctl
- [ ] Backup current `security_config.py`
- [ ] Note current database locations

## Step-by-Step Deployment

### 1. Backup Current Configuration

```bash
# SSH to production
ssh ro-z.net

# Navigate to project
cd /var/www/flyfun-apps

# Backup current config
cp web/server/security_config.py web/server/security_config.py.backup.$(date +%Y%m%d)
```

### 2. Pull Latest Changes

```bash
cd /var/www/flyfun-apps
git pull origin main
```

**What this brings:**
- `web/server/config_helpers.py` (NEW)
- Updated `web/server/main.py` (imports from both files)
- Updated `web/server/security_config.py.sample` (template)
- `shared/ga_friendliness/database.py` (readonly support)
- `shared/ga_friendliness/storage.py` (readonly support)
- `web/server/api/ga_friendliness.py` (readonly support)

### 3. Update security_config.py for Production

Edit `/var/www/flyfun-apps/web/server/security_config.py`:

**Option A: Start Fresh (Recommended)**
```bash
cd /var/www/flyfun-apps/web/server

# Copy from sample
cp security_config.py.sample security_config.py

# Edit with your production values
nano security_config.py
```

**Option B: Update Existing File**

Remove the old function definitions and update ALLOWED_DIR:

```python
# OLD (remove these lines if they exist):
def get_safe_db_path() -> str:
    # ... function body ...

def get_safe_rules_path() -> str:
    # ... function body ...

# etc.

# OLD (remove this):
ALLOWED_DIR = "./"

# NEW (add this):
ALLOWED_DIRS = [
    "/var/www/flyfun-apps",
    "/var/www/flyfun-apps/data",
    "/var/www/flyfun-apps/tmp",
]

# Make sure you have these production values:
ALLOWED_ORIGINS = [
    "https://maps.flyfun.aero",
    "https://flyfun.aero",
]

ALLOWED_HOSTS = [
    "maps.flyfun.aero",
    "flyfun.aero",
    "localhost",
    "127.0.0.1",
]
```

### 4. Update prod.env

Edit `/var/www/flyfun-apps/web/server/prod.env`:

```bash
# Add these new variables:
GA_META_DB=/var/www/flyfun-apps/tmp/ga_meta.sqlite
GA_META_READONLY=true
```

### 5. Verify Configuration

```bash
cd /var/www/flyfun-apps/web/server

python3 -c "
import sys
sys.path.insert(0, '../../')

# Test imports
from config_helpers import get_safe_db_path, get_safe_rules_path, get_safe_ga_meta_db_path, get_ga_friendliness_readonly
from security_config import ALLOWED_DIRS, ENVIRONMENT, ALLOWED_ORIGINS

print('✅ Configuration Test')
print(f'Environment: {ENVIRONMENT}')
print(f'Allowed Directories: {ALLOWED_DIRS}')
print(f'Allowed Origins: {len(ALLOWED_ORIGINS)} configured')
print()
print('Database Paths:')
print(f'  AIRPORTS_DB: {get_safe_db_path()}')
print(f'  RULES_JSON: {get_safe_rules_path()}')
print(f'  GA_META_DB: {get_safe_ga_meta_db_path()}')
print(f'  GA Readonly: {get_ga_friendliness_readonly()}')
"
```

Expected output:
```
✅ Configuration Test
Environment: production
Allowed Directories: ['/var/www/flyfun-apps', '/var/www/flyfun-apps/data', '/var/www/flyfun-apps/tmp']
Allowed Origins: 2 configured

Database Paths:
  AIRPORTS_DB: /var/www/flyfun-apps/data/airports.db
  RULES_JSON: /var/www/flyfun-apps/data/rules.json
  GA_META_DB: /var/www/flyfun-apps/tmp/ga_meta.sqlite
  GA Readonly: True
```

### 6. Fix Database Permissions (if needed)

If you still have the GA database readonly error:

```bash
# Fix permissions
sudo chown www-data:www-data /var/www/flyfun-apps/tmp/ga_meta.sqlite
sudo chmod 644 /var/www/flyfun-apps/tmp/ga_meta.sqlite

# Remove old WAL files
sudo rm -f /var/www/flyfun-apps/tmp/ga_meta.sqlite-wal
sudo rm -f /var/www/flyfun-apps/tmp/ga_meta.sqlite-shm
```

### 7. Restart Service

```bash
sudo systemctl restart euro-aip.service
```

### 8. Verify Service Started

```bash
# Check status
sudo systemctl status euro-aip.service

# Should show: Active: active (running)

# Check logs for success messages
sudo journalctl -u euro-aip.service -n 50 --no-pager
```

**Look for these log messages:**
```
GA Friendliness service initialized (readonly=True): /path/to/ga_meta.sqlite
Application startup complete
```

### 9. Test API Endpoints

```bash
# Test main API
curl https://maps.flyfun.aero/api/health

# Test GA endpoints
curl https://maps.flyfun.aero/api/ga/config
curl https://maps.flyfun.aero/api/ga/summary/LFMD

# Test in browser
# Visit: https://maps.flyfun.aero
```

### 10. Monitor for Errors

```bash
# Watch logs in real-time
sudo journalctl -u euro-aip.service -f

# Check for any errors
sudo journalctl -u euro-aip.service --since "5 minutes ago" | grep ERROR
```

## Verification Checklist

After deployment, verify:

- [ ] Service is running: `systemctl status euro-aip.service`
- [ ] No "readonly database" errors in logs
- [ ] Log shows "GA Friendliness service initialized (readonly=True)"
- [ ] Website loads: https://maps.flyfun.aero
- [ ] GA features work (check airport details for GA scores)
- [ ] No JavaScript errors in browser console
- [ ] API responds: `/api/health`, `/api/ga/config`

## Rollback Procedure

If something goes wrong:

```bash
# Stop service
sudo systemctl stop euro-aip.service

# Restore backup config
cd /var/www/flyfun-apps/web/server
cp security_config.py.backup.YYYYMMDD security_config.py

# Rollback git
cd /var/www/flyfun-apps
git reset --hard HEAD~1  # Or specific commit

# Start service
sudo systemctl start euro-aip.service
```

## Common Issues

### Issue: Import Error "No module named config_helpers"

**Cause**: Git pull didn't bring config_helpers.py

**Solution**:
```bash
cd /var/www/flyfun-apps
git status  # Check if file exists
ls -la web/server/config_helpers.py  # Verify file is there
```

### Issue: "ALLOWED_DIRS not defined"

**Cause**: security_config.py still has old ALLOWED_DIR

**Solution**: Update security_config.py to use ALLOWED_DIRS (plural)

### Issue: Still getting "readonly database" error

**Cause**: Permissions or WAL files

**Solution**:
```bash
# Remove WAL files
sudo rm -f /var/www/flyfun-apps/tmp/ga_meta.sqlite-*

# Fix permissions
sudo chown www-data:www-data /var/www/flyfun-apps/tmp/ga_meta.sqlite
```

### Issue: "GA Friendliness service disabled"

**Cause**: GA_META_DB not set or file not found

**Solution**:
1. Check prod.env has `GA_META_DB=/path/to/ga_meta.sqlite`
2. Verify file exists: `ls -la /path/to/ga_meta.sqlite`
3. Check path is in ALLOWED_DIRS

## Benefits After Deployment

✅ **No more readonly database errors** - GA database opens in read-only mode  
✅ **No more git conflicts** - Config values separate from logic functions  
✅ **Flexible directory structure** - Databases can live in different directories  
✅ **Auto-updating logic** - `git pull` brings new helper functions automatically  
✅ **Better security** - Multiple allowed directories with validation  

## Support

If you encounter issues:

1. Check logs: `sudo journalctl -u euro-aip.service -n 100`
2. Review config: `cat web/server/security_config.py`
3. Test imports: Run verification script from Step 5
4. Compare with backup: `diff web/server/security_config.py web/server/security_config.py.backup.*`

## Summary

This deployment brings:
- **GA readonly mode** prevents database corruption from web server
- **Config separation** eliminates git conflicts  
- **Multiple directories** allows flexible database organization

All designed to make production deployments smoother and safer! 🚀

