---
name: drupal-flake-process
description: Daily driver for drupal-flake development. Auto-detects active environments, provides URLs, drush commands, XDebug, logs, and lifecycle management. Cross-references drupal-flake-test for testing setup.
compatibility: opencode
metadata:
  framework: Drupal
  primary_tool: drupal-flake
  secondary_tools: [ddev, docker, drush]
  services: [nginx, php-fpm, mysql, process-compose]
  features: [auto-detection, daily-workflow, debugging, logs]
---

## Auto-Detection (Run First)

**⚠️ MUTUALLY EXCLUSIVE:** Use drupal-flake OR DDev, never both. Both use `*.ddev.site` domains but with different port strategies.

```bash
# Quick check - sets DRUPAL_ENV and BASE_URL
if ls /tmp/process-compose-*.sock 2>/dev/null | grep -q ""; then
  DRUPAL_ENV="drupal-flake"
  BASE_URL="http://$(grep DOMAIN .env 2>/dev/null | cut -d= -f2):$(grep PORT .env 2>/dev/null | cut -d= -f2)"
  echo "drupal-flake active: $BASE_URL"
elif which ddev >/dev/null 2>&1 && ddev describe 2>/dev/null | grep -q RUNNING; then
  DRUPAL_ENV="ddev"
  BASE_URL=$(ddev describe --json-output 2>/dev/null | jq -r '.raw.services.web.short_url' 2>/dev/null)
  echo "ddev active: $BASE_URL"
elif docker ps 2>/dev/null | grep -qiE "(drupal|php|nginx)"; then
  DRUPAL_ENV="docker"
  echo "docker containers running"
else
  DRUPAL_ENV="none"
  echo "No environment detected. Run: nix develop && start-detached"
fi
```

### Domain & Port Strategy

| Environment | Domain | Port | Example URL |
|-------------|--------|------|-------------|
| **drupal-flake** | `*.ddev.site` | Custom (e.g., 2675) | `http://mysite.ddev.site:2675` |
| **DDev** | `*.ddev.site` | Standard (80/443) | `https://mysite.ddev.site` |

**Never run both simultaneously** - they would conflict on the domain. If switching, stop one before starting the other.

## Daily Development Workflow

### 1. Get Site URL

**drupal-flake:**
```bash
# Auto-construct from .env
export DOMAIN=$(grep DOMAIN .env | cut -d= -f2)
export PORT=$(grep PORT .env | cut -d= -f2)
echo "http://${DOMAIN}:${PORT}"

# Or one-liner
BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
curl -s -o /dev/null -w "%{http_code}" "$BASE_URL"  # Should be 200
```

**Port calculation helper:** "cms" = 267 (c=2,m=6,s=7) + 2 = **2675**

### 2. Drush Commands

**drupal-flake:**
```bash
# Standard commands (no XDebug - faster)
drush status
drush uli                          # Login link
drush cache:rebuild               # Clear cache
drush config:export -y            # Export config
drush sql:dump > backup.sql       # Database backup

# For kickstart projects, use:
./bin/drush [command]

# XDebug version (slower - use only when debugging)
xdrush [command]                  # Runs with XDebug on port 9003
```

**Available commands:**
- `drush` - Standard drush (fast, no XDebug)
- `xdrush` - Drush with XDebug enabled
- `xphpunit` - PHPUnit with XDebug
- `xcomposer` - Composer with XDebug

### 3. XDebug Debugging

**Trigger XDebug:**
```bash
# Via environment (for CLI)
export XDEBUG_CONFIG="idekey=PHPSTORM"

# Via URL parameter (for web)
# Add to any URL: ?XDEBUG_TRIGGER=1
# Example: http://localhost:2675?XDEBUG_TRIGGER=1

# XDebug runs on port 9003
# Config in flake: xdebug.mode=debug, xdebug.start_with_request=trigger
```

**Pre-configured commands:**
- `drush` - Standard drush (daily use, fast)
- `xdrush` - Drush with XDebug (debugging only, slower)
- `xphpunit` - PHPUnit with XDebug on port 9003

### 4. Logs & Monitoring

**Watchdog logs (Drupal dblog):**
```bash
drush watchdog:show --tail          # Follow logs
drush watchdog:show --type=error   # Errors only
drush watchdog:delete all          # Clear logs
```

**System logs (process-compose):**
```bash
pc-logs nginx                       # Nginx access/error logs
pc-logs php-fpm                     # PHP errors
pc-logs mysql                     # MySQL queries/errors
pc-logs --follow                  # Follow all logs
```

**Log files directly:**
```bash
tail -f data/logs/nginx-error.log
tail -f data/logs/php-fpm-error.log
```

### 5. Database Operations

```bash
# Export
drush sql:dump > $(date +%Y%m%d)-backup.sql

# Import
drush sql:query --file=backup.sql

# Connect directly
mysql -u root -S data/db/mysql.sock [database]
```

## Environment Detection Details

### drupal-flake (Nix)
```bash
# Active when socket exists
ls -la /tmp/process-compose-*.sock 2>/dev/null

# In shell check
echo $DIRENV_DIR  # or run: nix develop

# Key .env variables
# PROJECT_NAME=foo, DOMAIN=foo.ddev.site, PORT=2675, PHP_VERSION=php84
```

### DDev (Alternative to drupal-flake)
⚠️ **Never auto-start without explicit request.** DDev is an alternative container-based solution - don't use with drupal-flake simultaneously.
```bash
ddev describe 2>/dev/null | grep -E "(RUNNING|short_url)"
# DDev URLs: https://*.ddev.site (standard ports 80/443)
```

### Docker
```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -iE "(drupal|php|nginx)"
```

## Environment Comparison

**drupal-flake vs DDev: Mutually Exclusive Alternatives**

| Aspect | drupal-flake (Nix) | DDev (Docker) |
|--------|-------------------|---------------|
| **Domain** | `*.ddev.site` | `*.ddev.site` |
| **Port** | Custom (e.g., 2675) | Standard 80/443 |
| **URL Example** | `http://mysite.ddev.site:2675` | `https://mysite.ddev.site` |
| **When to use** | Nix-based, lightweight | Full container orchestration |
| **Conflict** | ⚠️ Don't run simultaneously | ⚠️ Don't run simultaneously |

**If switching environments:**
```bash
# Stop drupal-flake before starting DDev
pc-stop  # or stop-all
# Then: ddev start

# Stop DDev before starting drupal-flake
ddev stop
# Then: nix develop && start-detached
```

## Lifecycle Commands

```bash
# Start
nix run                    # TUI (interactive)
start-detached            # Background

# Stop
pc-stop                   # Graceful
stop-all                  # Force kill

# Status
pc-status                 # What's running
pc-attach                 # Re-attach to TUI
```

## Troubleshooting Quick Fixes

| Issue | Fix |
|-------|-----|
| mysql.sock error | `git init && git add .env .gitignore` |
| .env not loading | `direnv reload` or `cd . && cd -` |
| Port conflict | `lsof -i :PORT` then change PORT in .env |
| Stale socket | `rm -f /tmp/process-compose-*.sock` |
| Site not responding | Check HTTP 200: `curl -s -o /dev/null -w "%{http_code}" $BASE_URL` |

## Testing Setup

**For PHPUnit, browser testing, CI/CD:**
→ Load `drupal-flake-test` skill

**Quick test check:**
```bash
# Check if tests are configured
ls phpunit.xml 2>/dev/null || echo "Run: phpunit-setup"
```

## Workflow Summary

**Daily pattern:**
1. Auto-detect environment (socket check)
2. Get URL from .env: `http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)`
3. Use `drush` (fast) or `./bin/drush` for management, `drush uli` for login
4. Watch logs: `drush watchdog:show --tail` or `pc-logs --follow`
5. Debug: Use `xdrush` (XDebug enabled) or add `?XDEBUG_TRIGGER=1` to URLs
6. Test: Load `drupal-flake-test` skill for PHPUnit/Puppeteer
