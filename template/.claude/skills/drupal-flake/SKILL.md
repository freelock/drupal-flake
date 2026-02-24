---
name: drupal-flake
description: Work with Drupal development environments using drupal-flake (Nix), DDev, or Docker. Detects active environments, handles NEW project initialization with interactive setup, and provides all development commands.
compatibility: opencode
metadata:
  framework: Drupal
  primary_tool: drupal-flake
  secondary_tools: [ddev, docker]
  services: [nginx, php-fpm, mysql, process-compose]
  features: [new-project-init, environment-detection, testing-setup]
---

## Environment Detection Priority

When starting work on a Drupal project, detect the active environment in this order:

### 1. Check drupal-flake (Nix-based)

**Check if running:**
```bash
# Method 1: Check for socket file (fastest)
ls -la /tmp/process-compose-*.sock 2>/dev/null

# Method 2: Run pc-status (if available)
pc-status

# Method 3: Check for flake.nix and .env
ls flake.nix .env 2>/dev/null
```

**If NOT in shell:**
- Check for direnv: `echo $DIRENV_DIR` - if set, environment should be loaded
- If direnv not active or failing: Run `nix develop` to enter the environment
- Once in shell, commands like `pc-status`, `start`, etc. become available

**If flake.nix exists but environment not running:**
- Start with: `nix run` (interactive) or `start-detached` (background)
- Wait for `pc-status` to show "running and ready"
- Then attach with `pc-attach` if needed

### 2. Check DDev (if drupal-flake not running)

**Check if DDev exists and is running:**
```bash
# First, check if ddev is installed
which ddev

# If installed, check if this project is configured
ls .ddev/config.yaml 2>/dev/null

# If configured, check status WITHOUT starting it
ddev describe 2>/dev/null | grep -E "(RUNNING|STARTING|STOPPED)"
```

**⚠️ IMPORTANT:** Never run `ddev start` unless the user explicitly requests it. Some developers intentionally keep DDev stopped.

### 3. Check Docker (if neither above is running)

**Check for Docker containers:**
```bash
# Check if docker is available
which docker

# Look for running containers with PHP, Nginx, or Apache
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -iE "(php|nginx|apache|drupal)"
```

**Check for docker-compose or similar:**
```bash
ls docker-compose.yml docker-compose.yaml compose.yml 2>/dev/null
```

## Configuration Discovery

### For drupal-flake

Once environment is detected or started, read configuration from `.env`:

```bash
# Read project configuration
cat .env 2>/dev/null | grep -E "^(PROJECT_NAME|DOMAIN|PORT|DOCROOT|PHP_VERSION)="
```

**Key variables:**
- `PROJECT_NAME` - Used in socket path `/tmp/process-compose-${PROJECT_NAME}.sock`
- `DOMAIN` - Local domain (e.g., `myproject.ddev.site`)
- `PORT` - HTTP port (default: 8088, new projects default to 8080)
- `DOCROOT` - Web root directory (default: `web`)
- `PHP_VERSION` - PHP version (options: php74, php83, php84; new projects default to php84)

**Construct base URL:**
```
http://${DOMAIN}:${PORT}
```

Example: `http://myproject.ddev.site:8088`

### For DDev

```bash
ddev describe --json-output | jq -r '.raw.services.web | "\(.short_url) - \(.status)"'
```

### For Docker

Extract ports from container info and construct URLs.

## Available Commands by Environment

### drupal-flake Commands

**Environment Management:**
- `nix run` or `start` - Start dev environment (interactive TUI)
- `start-detached` - Start in background mode
- `pc-stop` - Stop current project's environment
- `stop-all` - Stop ALL process-compose environments
- `pc-status` - Check if running and healthy
- `pc-attach` - Attach to running TUI
- `nix develop` - Enter shell without starting services

**Site Setup:**
- `start-demo [package] [name] [options]` - Create new Drupal site
  - Examples:
    - `start-demo` - Default drupal/cms
    - `start-demo drupal/recommended-project my-site`
    - `start-demo phenaproxima/xb-demo xb-site --stability=dev`
- `start-config` - Install from existing config (**WARNING:** clobbers database!)
- `refresh-flake [path]` - Update flake from Drupal.org or local path

**Development Tools:**
- `xdrush [command]` - Drush with Xdebug (port 9003)
- `xphpunit [options]` - PHPUnit with Xdebug
- `phpunit-setup` - Create phpunit.xml configuration
- `phpunit-module <module-name>` - Run tests for specific module
- `phpunit-custom` - Run tests for all custom modules/themes
- `nix-settings` - Add settings.nix.php
- `setup-starship-prompt` - Configure shell prompt
- `?` - Show all commands

**Testing URLs:**
- XDebug triggers via URL params: `?XDEBUG_PROFILE=1`

### DDev Commands

**Status:** `ddev describe`
**Start:** `ddev start` (only if requested)
**Stop:** `ddev stop`
**Drush:** `ddev drush [command]`
**SSH:** `ddev ssh`

### Docker Commands

**Check status:** `docker compose ps` or `docker ps`
**Logs:** `docker compose logs -f [service]`
**Shell:** `docker compose exec [container] bash`

## Installation and Setup Options

### Initial Project Setup

If this is a fresh project or needs setup:

**Option 1: New Site (start-demo)**
```bash
# Interactive - will prompt for package and name
start-demo

# Or specify everything
start-demo drupal/recommended-project my-project --stability=stable
```

**Option 2: From Config (start-config)**
```bash
# Only if config/sync exists and user wants to restore
start-config
```

**Option 3: Existing Codebase**
```bash
# Just start the environment
nix run
# or
start-detached
```

### PHPUnit Configuration

**Quick setup:**
```bash
phpunit-setup
```

This creates `phpunit.xml` configured for this environment with correct paths and database connection.

**Run tests:**
```bash
# All tests
phpunit-custom

# Specific module
phpunit-module my_module

# With XDebug
xphpunit --filter MyTest
```

### XDebug Setup

**For debugging (IDE integration):**
1. XDebug is pre-configured on port 9003
2. Use wrappers: `xdrush` and `xphpunit` 
3. Or manually add `?XDEBUG_SESSION_START=1` to URLs

**For profiling:**
- Profiles save to `data/xdebug_profiles/`
- Trigger with `?XDEBUG_PROFILE=1` URL param
- Use tools like Webgrind or KCacheGrind to analyze

## Workflow: Starting Work on a Project

**Step 1: Detect environment**
```bash
# Check drupal-flake first
pc-status 2>/dev/null || echo "Not running"

# Check DDev (if ddev exists)
which ddev && ddev describe 2>/dev/null | head -5

# Check Docker
which docker && docker ps --format "{{.Names}}" | grep -iE "(php|nginx|apache)"
```

**Step 2: Check if this is a NEW project**

If all environment checks return nothing, check for existing Drupal code:
```bash
# Check for existing Drupal
ls web/index.php 2>/dev/null || ls docroot/index.php 2>/dev/null || ls index.php 2>/dev/null

# Check for .env configuration
cat .env 2>/dev/null | head -5
```

**If NO Drupal code found AND NO .env configured → NEW PROJECT SETUP NEEDED**

Proceed to "New Project Initialization" workflow below.

**Step 3: Start if needed**

If nothing running and user wants to start:
```bash
# Preferred: Background mode (non-blocking)
start-detached

# Or interactive (blocking TUI)
nix run
```

**Step 4: Wait for readiness (CRITICAL: Check HTTP, not just process count)**

⚠️ **IMPORTANT:** During setup, you'll see process counts like "3/7 running" or "4/7 running". This is NORMAL!

**Understanding Process States:**
- **Setup processes** (`cms`, `nix-settings`, `init`) are designed to COMPLETE and exit (0)
- **Service processes** (`php-fpm`, `nginx`, `mysql`) stay running persistently
- A successful setup shows ~3-4 persistent services running after init processes complete

**CORRECT way to check completion:**
```bash
# Method 1: Check HTTP response (MOST RELIABLE)
export BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
until curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200"; do
  echo "Waiting for site to respond..."
  sleep 5
done
echo "✅ Site is up at $BASE_URL"

# Method 2: Check if web/index.php exists AND services are running
ls web/index.php 2>/dev/null && pc-status | grep -q "running" && echo "✅ Ready"

# Method 3: Check process-compose logs for completion
tail -20 data/process-compose.log | grep -E "(completed|Drupal CMS already installed|ready)"
```

**DON'T rely on process count alone!** Setup processes are supposed to finish.

## New Project Initialization

When starting with an empty directory (no Drupal code, no .env), follow this workflow:

### Prerequisites Check

**1. Initialize Git Repository (CRITICAL to prevent Nix errors)**

⚠️ **Without git, Nix will fail when MySQL starts** because it creates socket files that Nix can't handle during directory scanning.

```bash
# Check if git is already initialized
git status 2>/dev/null || echo "Need to init git"

# Initialize git (do this BEFORE starting any services!)
git init

# Add essential files (flake and configs) - Nix uses git to determine what to include
git add flake.nix flake.lock .env .envrc .gitignore .services/
# Note: No commit needed - 'git add' is sufficient for Nix evaluation
# User can commit when they're ready
```

**Why this matters:**
- Nix flakes use git to determine which files to include
- The `data/` directory is gitignored (contains MySQL, logs, sockets)
- Without git, Nix sees the `mysql.sock` file and fails with "unsupported type" error
- Without git, changes to `.env` won't be picked up properly
- **Only `git add` is needed** - Nix evaluates based on staged files, not commits

**Why this matters:**
- Nix flakes use git to determine which files to include
- The `data/` directory is gitignored (contains MySQL, logs, sockets)
- Without git, Nix sees the `mysql.sock` file and fails with "unsupported type" error
- Without git, changes to `.env` won't be picked up properly

**2. Ensure flake.nix exists**
```bash
ls flake.nix 2>/dev/null || echo "Need to run: nix flake init -t /path/to/drupal-flake"
```

**3. Get current directory name for defaults**
```bash
basename "$PWD"
```

### Step 1: Prompt User for Configuration

**Required Questions:**

1. **Project Name**
   - Default: current directory name (e.g., `cms`)
   - Used for: socket paths, domain generation

2. **HTTP Port** (Suggest intelligently based on project name)
   - Algorithm: Convert project name letters to phone keypad numbers
   - `a-e=4, f-l=5, m-q=6, r-t=7, u-x=8, y-z=9`
   - Example: `cms` → c(2)=6, m(1)=6, s(1)=7 → suggest **6677** or **7667**
   - Range: 1024-65535 (4-digit ports 4000-9999 work well)
   - Check if suggested port is available: `lsof -i :PORT` should return nothing
   - **Port Suggestion Script:**
   ```bash
   suggest_port() {
     local name="${1:-$(basename "$PWD")}"
     local pad="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
     local port=""
     local i=0
     name=$(echo "$name" | tr '[:lower:]' '[:upper:]')
     while [ $i -lt 4 ] && [ $i -lt ${#name} ]; do
       local char="${name:$i:1}"
       local pos=$(expr index "$pad" "$char")
       if [ $pos -ge 1 ] && [ $pos -le 3 ]; then port="${port}4"      # ABC
       elif [ $pos -ge 4 ] && [ $pos -le 6 ]; then port="${port}5"   # DEF  
       elif [ $pos -ge 7 ] && [ $pos -le 9 ]; then port="${port}6"   # GHI
       elif [ $pos -ge 10 ] && [ $pos -le 12 ]; then port="${port}7" # JKL
       elif [ $pos -ge 13 ] && [ $pos -le 15 ]; then port="${port}8" # MNO
       elif [ $pos -ge 16 ] && [ $pos -le 19 ]; then port="${port}9" # PQRS
       elif [ $pos -ge 20 ] && [ $pos -le 22 ]; then port="${port}8" # TUV
       elif [ $pos -ge 23 ] && [ $pos -le 26 ]; then port="${port}9" # WXYZ
       fi
       i=$((i + 1))
     done
     echo "${port:-8080}"
   }
   # Usage: suggest_port "cms" → outputs 7667
   ```

3. **PHP Version**
   - Options: `php74`, `php83`, `php84` (default: `php84`)
   - Note: php74 requires legacy nixpkgs, others use standard

4. **Starting Point** (Drupal Distribution)
   - **Drupal CMS 2.0** → `drupal/cms` (latest, includes modern features)
   - **Drupal Commerce Kickstart** → `drupalcommerce/commerce_kickstart`
   - **Vanilla Drupal Core** → `drupal/recommended-project`
   - **Other** → Let user specify package name

### Step 2: Create .env File

Create `.env` with all user selections:

```bash
cat > .env << 'EOF'
PROJECT_NAME=your-project-name
DOMAIN=your-project-name.ddev.site
PORT=8080
PHP_VERSION=php84
DOCROOT=web
EOF
```

**Important:** The .env file MUST be created BEFORE running start-demo so the environment uses correct settings.

### Step 3: Select Drupal Package

Based on user choice:

| Starting Point | Composer Package | Post-Install Recipe |
|----------------|------------------|---------------------|
| Drupal CMS 2.0 | `drupal/cms` | `drush site:install recipes/byte --yes` |
| Commerce Kickstart | `drupalcommerce/commerce_kickstart` | Standard install or check docs |
| Vanilla Core | `drupal/recommended-project` | `drush site:install standard --yes` |
| Custom | User-provided | Ask user for install command |

### Step 4: Initialize Project

**Start environment and install Drupal:**

**Preferred Method - Detached Mode with Recipe:** Use `start-demo --detached` and set the `DEMO_RECIPE` environment variable to install a specific recipe automatically.

```bash
# Method 1: Using start-demo --detached with recipe (RECOMMENDED for agents)
# This installs the package AND the recipe in one command
export DEMO_RECIPE="recipes/byte"  # For Drupal CMS 2.0 demo content
start-demo --detached [PACKAGE_NAME] [PROJECT_NAME]
# Example: 
# export DEMO_RECIPE="recipes/byte"
# start-demo --detached drupal/cms my-project

# Method 2: Interactive mode (blocks until complete, shows TUI)
export DEMO_RECIPE="recipes/byte"
start-demo [PACKAGE_NAME] [PROJECT_NAME]

# Method 3: Using environment variables with start-detached
export DEMO_DRUPAL_PACKAGE="[PACKAGE_NAME]"
export DEMO_RECIPE="recipes/byte"
start-detached
```

**Available Recipes:**
- `recipes/byte` - Drupal CMS 2.0 full demo (workspaces, content, etc.)
- `standard` - Standard Drupal installation
- `minimal` - Minimal installation
- (leave empty for default install)

**Wait for environment:**
```bash
# Wait for environment to be ready
until pc-status | grep -q "running and ready"; do
  echo "Waiting for environment..."
  sleep 3
done
```

**⚠️ Installation Time Warning:**
The installation process (downloading + recipe installation) takes 2-5 minutes depending on hardware. The `recipes/byte` recipe especially takes time as it sets up workspaces, content types, and demo content. Inform the user: "Installing now, this will take 2-5 minutes..."

**Alternative: Use nix run .#demo directly**
```bash
# This will use the package from environment or default to drupal/cms
# The .env file must already exist with correct PROJECT_NAME
# Use --detached flag to avoid TUI
export DEMO_RECIPE="recipes/byte"
nix run .#demo -- --detached [PACKAGE] [PROJECT_NAME]
```

### Step 5: Verify Installation and Get Credentials

**Check site is responding:**
```bash
curl -s -o /dev/null -w "%{http_code}" "http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
# Should return 200
```

**Get admin credentials:**
```bash
# If you captured the install output, extract from there
# Otherwise generate a one-time login link:
drush uli
# This outputs something like:
# http://your-project.ddev.site:PORT/user/reset/1/123456789/xyz-token

# Or create a new password:
drush upwd admin --password="your-secure-password"
```

### Step 6: Configure Development Environment

**Optional but recommended:**
```bash
# Setup PHPUnit if testing will be needed
phpunit-setup

# Check status
pc-status
?  # Show available commands
```

### Complete New Project Workflow

```
1. Check if flake.nix exists
   NO → Run: nix flake init -t /path/to/drupal-flake
   
2. **CRITICAL: Initialize git BEFORE doing anything else**
   ```bash
   git init
   git add flake.nix flake.lock .env .envrc .gitignore .services/
   # Note: git add is sufficient - Nix uses staged files, user can commit later
   ```
   
   ⚠️ **If you skip this:** MySQL socket will cause Nix to fail!
   
3. Check if .env exists AND web/index.php exists
   YES → Existing project, skip to environment detection
   NO  → Continue with initialization
   
4. **CRITICAL - MUST PROMPT USER:** Don't auto-detect or skip!
   
   **Always ask these 4 questions:**
   
   a. **Project name?**
      - Check: basename "$PWD" → e.g., "cms"
      - Suggest: "What project name should I use? (default: cms)"
      - Wait for user confirmation or input
   
   b. **Port?** 
      - Calculate: Using phone keypad on "cms" → 7667
      - Suggest: "What port should I use? (suggested: 7667, check: lsof -i :7667)"
      - Wait for user confirmation or input
   
   c. **PHP version?**
      - Suggest: "Which PHP version? (default: php84, options: php74, php83, php84)"
      - Wait for user confirmation
   
   d. **Starting point?**
      - Explain: "Drupal CMS 2.0 includes full demo content via 'byte' recipe (~3-5 min install). Vanilla is minimal Drupal core (~1-2 min)."
      - Options: "1) Drupal CMS 2.0 (full demo), 2) Commerce Kickstart (e-commerce), 3) Vanilla core (minimal)"
      - Wait for user selection

4. Write .env file with CONFIRMED user selections
   
5. **Initialize git repository (if not already done):**
   ```bash
   git init 2>/dev/null || echo "Already initialized"
   git add .env .gitignore flake.nix flake.lock .envrc .services/ 2>/dev/null
   # Note: Only 'git add' needed - Nix evaluates staged files, commit optional
   ```
   
6. Determine package and recipe based on user choice:
   - Choice 1 (CMS) → drupal/cms + DEMO_RECIPE="recipes/byte"
   - Choice 2 (Commerce) → drupalcommerce/commerce_kickstart + no recipe
   - Choice 3 (Vanilla) → drupal/recommended-project + no recipe
   
7. Enter nix shell to load environment:
   ```bash
   nix develop
   # Or if direnv is working, it should auto-load
   ```
   
8. Set recipe environment variable and start in detached mode:
   ```bash
   export DEMO_RECIPE="recipes/byte"  # Only for CMS choice
   start-demo --detached [package] [project-name]
   ```
   
9. **Monitor installation (⚠️ TAKES 2-5 MINUTES):**
   
   **DON'T wait for "all processes running" - that's WRONG!**
   
   **Better Progress Monitoring (shows actual progress):**
   ```bash
   export BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
   export LOG_FILE="data/demo-detached.log"
   
   echo "Starting installation monitor..."
   echo "Site will be available at: $BASE_URL"
   echo "Streaming progress from: $LOG_FILE"
   echo ""
   
   # Monitor with meaningful progress updates
   while true; do
     # Check if site is up (success condition)
     HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null)
     if [ "$HTTP_STATUS" = "200" ]; then
       echo ""
       echo "✅ SUCCESS! Site is responding at $BASE_URL"
       break
     fi
     
     # Check process-compose status for context
     PC_STATUS=$(pc-status 2>/dev/null | grep -oE "[0-9]+/[0-9]+ running" || echo "unknown")
     
     # Show latest meaningful log line (last 5 lines, filtered for progress)
     LATEST_PROGRESS=$(tail -5 "$LOG_FILE" 2>/dev/null | grep -E "(Installing|Creating|Recipe|Composer|Drupal)" | tail -1 || echo "")
     
     # Timestamp and status
     TIMESTAMP=$(date '+%H:%M:%S')
     
     if [ -n "$LATEST_PROGRESS" ]; then
       echo "[$TIMESTAMP] $PC_STATUS | $LATEST_PROGRESS"
     else
       echo "[$TIMESTAMP] $PC_STATUS | Waiting... (HTTP: $HTTP_STATUS)"
     fi
     
     sleep 10
   done
   ```
   
   **What to expect during installation:**
   - **0-30 seconds:** Composer downloading packages ("Installing drupal/cms...")
   - **30-60 seconds:** Database setup ("Creating project...")
   - **1-2 minutes:** Recipe installation ("Applying recipe recipes/byte...")
   - **2-3 minutes:** Content creation ("Creating content types...")
   - **3-5 minutes:** Final setup and cache clearing
   
   **Alternative simple HTTP check (less verbose):**
   ```bash
   # If you prefer minimal output
   export BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
   until curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200"; do
     echo "$(date '+%H:%M:%S'): Installing... (check $LOG_FILE for details)"
     sleep 15
   done
   echo "✅ Site is responding at $BASE_URL"
   ```
   
   **Manual progress check (if you want to watch logs yourself):**
   ```bash
   # Watch full installation log
   tail -f data/demo-detached.log
   
   # Or check specific stages
   grep -E "(Installing|Recipe|created|completed)" data/demo-detached.log
   ```
   
   **Expected behavior:**
   - Setup processes complete and exit (this is NORMAL)
   - Only 3-4 persistent services remain (php, nginx, mysql)
   - Process count like "3/7 running" or "4/7 running" is SUCCESS, not failure
   
10. **Get credentials and verify:**
    ```bash
    # Check if site responds
    curl -s -o /dev/null -w "%{http_code}" "$BASE_URL"
    # Should output: 200
    
    # Get admin login link
    drush uli
    # Outputs: http://cms.ddev.site:7667/user/reset/1/xxxxx/yyyyy
    ```
    
11. **Report success to user:**
    ```
    ✅ Drupal installation complete!
    
    Site URL: http://[domain]:[port]
    Admin login: [drush uli output]
    Recipe installed: [recipes/byte or none]
    Installation time: ~[X] minutes
    
    Available commands:
    - pc-status     Check environment status
    - ?             Show all commands
    - drush [cmd]   Run Drush commands
    ```
   
7. Set recipe environment variable and start in detached mode:
   ```bash
   export DEMO_RECIPE="recipes/byte"  # Only for CMS choice
   start-demo --detached [package] [project-name]
   ```
   
8. **Monitor installation (⚠️ TAKES 2-5 MINUTES):**
   
   **DON'T wait for "all processes running" - that's WRONG!**
   
   **Correct completion checks:**
   ```bash
   # Method 1: HTTP check (BEST - check every 10 seconds)
   export BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
   until curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200"; do
     echo "$(date): Waiting for site... (checking $BASE_URL)"
     sleep 10
   done
   echo "✅ Site is responding at $BASE_URL"
   
   # Method 2: Check logs for completion message
   tail -50 data/demo-detached.log | grep -E "(completed|installed|ready)"
   
   # Method 3: Check for web/index.php existence
   ls web/index.php 2>/dev/null && echo "✅ Drupal code present"
   ```
   
   **Expected behavior:**
   - Setup processes complete and exit (this is NORMAL)
   - Only 3-4 persistent services remain (php, nginx, mysql)
   - Process count like "3/7 running" or "4/7 running" is SUCCESS, not failure
   
9. **Get credentials and verify:**
   ```bash
   # Check if site responds
   curl -s -o /dev/null -w "%{http_code}" "$BASE_URL"
   # Should output: 200
   
   # Get admin login link
   drush uli
   # Outputs: http://cms.ddev.site:7667/user/reset/1/xxxxx/yyyyy
   
   # Or check install logs for credentials:
   grep -E "(Username|Password|Congratulations)" data/demo-detached.log
   ```
   
10. **Report success to user:**
    ```
    ✅ Drupal installation complete!
    
    Site URL: http://[domain]:[port]
    Admin login: [drush uli output]
    Recipe installed: [recipes/byte or none]
    Installation time: ~[X] minutes
    
    Available commands:
    - pc-status     Check environment status
    - ?             Show all commands
    - drush [cmd]   Run Drush commands
    ```
```

## Troubleshooting

### pc-status shows "socket does not exist"
- Environment not started: Run `start-detached`
- Wrong project: Check `.env` for PROJECT_NAME, verify socket path

### pc-status shows "starting up" but never ready
- Check logs: `tail -f data/process-compose.log`
- Common issues: Port already in use, MySQL data corruption
- Nuclear option: `stop-all && rm -rf data/ && start-detached`

### nix develop fails
- Try: `nix flake update` then retry
- Or: `rm -rf ~/.cache/nix/` (slow, redownloads everything)

### "command not found" errors
- Not in nix shell: Run `nix develop` first
- Or if direnv not working: `eval "$(direnv export bash)"`

### mysql.sock "unsupported type" error / "file has an unsupported type"

**Error:** `error: file '/path/to/data/PROJECT-db/mysql.sock' has an unsupported type`

**Root Cause:** Nix cannot handle socket files when evaluating the flake. MySQL creates `mysql.sock` in the `data/` directory, and if Nix sees it (because there's no git or data/ isn't gitignored), it fails.

**Prevention (BEST):**
1. **Initialize git BEFORE starting services:**
   ```bash
   git init
   git add flake.nix flake.lock .env .envrc .gitignore .services/
   # Note: Only 'git add' is needed - Nix evaluates staged files
   ```

2. **Ensure .gitignore includes:**
   ```
   data/
   *.sock
   mysql.sock
   ```

3. **The data/ directory is gitignored**, so Nix (via git) won't see the socket file.

**Solutions if already hit:**

**Option 1: Initialize git now (if services haven't started)**
```bash
# Stop services if running
stop-all 2>/dev/null || true

# Remove socket files
rm -f data/*/mysql.sock

# Initialize git
git init
git add flake.nix flake.lock .env .envrc .gitignore .services/
# Note: commit optional - git add is sufficient for Nix
```

2. **Ensure .gitignore includes:**
   ```
   data/
   *.sock
   mysql.sock
   ```

3. **The data/ directory is gitignored**, so Nix (via git) won't see the socket file.

**Solutions if already hit:**

**Option 1: Initialize git now (if services haven't started)**
```bash
# Stop services if running
stop-all 2>/dev/null || true

# Remove socket files
rm -f data/*/mysql.sock

# Initialize git
git init
git add flake.nix flake.lock .env .envrc .gitignore .services/
git commit -m "Initial setup"

# Now start services
start-detached
```

**Option 2: Move socket to /tmp (alternative)**
Change the socket location in `.env`:
```bash
echo 'DB_SOCKET=/tmp/${PROJECT_NAME}-mysql.sock' >> .env
```

**Option 3: Use --impure flag (last resort)**
```bash
nix develop --impure
```
This tells Nix to ignore git and track all files, but may still fail on sockets.

**Why this happens:**
- Nix flakes use git to determine which files to include in the evaluation
- Socket files (like `mysql.sock`) are special file types that Nix cannot process
- Without git, Nix scans the entire directory and hits the socket
- With git, `.gitignore` prevents the socket from being seen by Nix

**Best Practice:** Always `git init` immediately after `nix flake init`, BEFORE starting any services.

### Agent didn't ask for project name/port and used defaults
**Problem:** The agent started setup without asking for configuration, resulting in wrong project name or port.

**Cause:** The agent may have found an existing `.env` file or assumed defaults without prompting.

**Prevention:**
1. **Always check BEFORE creating .env:**
   ```bash
   ls .env 2>/dev/null && cat .env || echo "No .env yet"
   ```

2. **Explicitly prompt for each value:**
   - "What project name should I use? (detected: $(basename $PWD))"
   - "What port should I use? (suggested: $(suggest_port), check: lsof -i :PORT)"
   - "Which PHP version? (default: php84)"
   - "Which starting point? (explain options)"

3. **Wait for user confirmation** - don't proceed with defaults

**If already started with wrong config:**
1. Stop: `stop-all`
2. Delete data: `rm -rf data/ web/ .env`
3. Re-initialize with correct values

### Setup shows "3/7 running" or "4/7 running" - Agent thinks it failed
**Problem:** Agent sees process count like "3/7 running" and thinks installation failed or is incomplete.

**Reality:** This is **SUCCESS**! Setup processes are designed to complete and exit.

**What happens:**
- **Setup processes** (cms, nix-settings, init) → Run once, then exit with code 0 ✓
- **Service processes** (php-fpm, nginx, mysql) → Stay running persistently
- **Result:** "3/7 running" means 3 persistent services running, 4 setup processes completed

**Correct detection:**
```bash
# WRONG:
pc-status | grep "3/7 running" && echo "Failed"  # NO!

# CORRECT:
export URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
if curl -s -o /dev/null -w "%{http_code}" "$URL" | grep -q "200"; then
  echo "✅ SUCCESS - Site is responding at $URL"
else
  echo "⏳ Still waiting..."
fi
```

### Credentials not captured - Install completed but no login info
**Problem:** Installation finished but agent doesn't have username/password to report.

**Solutions:**

1. **Generate fresh login link (BEST):**
   ```bash
   drush uli
   # Output: http://cms.ddev.site:7667/user/reset/1/xxxxx/yyyyyy
   ```

2. **Check install logs:**
   ```bash
   # Look for credentials in detached log
   grep -E "(Username|Password|admin)" data/demo-detached.log
   
   # Or check process-compose logs
   grep -E "(Congratulations|installed)" data/process-compose.log
   ```

3. **Set known password:**
   ```bash
   drush upwd admin --password="secure-password-here"
   echo "Admin password set to: secure-password-here"
   ```

4. **Default credentials (if install used --account-pass):**
   - Username: admin
   - Password: admin (if you used `--account-pass=admin`)

**Prevention:** Always run `drush uli` after installation completes to get fresh login link.

### Installation completed but agent still waiting

### .env changes not picked up / Wrong project name or URL
The Nix flake reads `.env` at **evaluation time**, not shell entry time. If you modify `.env` after the shell is loaded:

**Symptoms:**
- `?` command shows wrong URL (e.g., `drupal-demo.ddev.site:8088` instead of your custom values)
- Shell prompt shows wrong project name
- `pc-status` looks for wrong socket path

**Solutions:**
1. **Reload direnv**: `direnv reload` or `eval "$(direnv export bash)"`
2. **Exit and re-enter**: `exit` then `cd .` (triggers direnv reload)
3. **Force nix re-evaluation**: `nix flake update` then re-enter shell
4. **Clear nix cache**: `rm -rf ~/.cache/nix/` (nuclear option, slow)

**Best Practice:** Create `.env` BEFORE first entering the directory, or always reload after changes.

### mysql.sock "unsupported type" error
**Error:** `file '/path/to/data/PROJECT-db/mysql.sock' has an unsupported type`

This happens when Nix tries to evaluate the flake but encounters the MySQL socket file, which is a special file type that Nix can't handle during directory scanning.

**Solutions:**
1. **Stop the environment first**: `stop-all` or `pc-stop`
2. **Remove socket files before nix commands**:
   ```bash
   rm -f data/*/mysql.sock
   nix flake update
   ```
3. **Use --impure flag** (if needed): `nix develop --impure`

### Recipe not installed / Wrong install type
If you ran `start-demo` but got a generic install instead of the recipe (e.g., Mercury theme instead of byte recipe):

**Cause:** The `DEMO_RECIPE` environment variable wasn't set before running start-demo.

**Solution:** Set the recipe BEFORE running start-demo:
```bash
export DEMO_RECIPE="recipes/byte"
start-demo --detached drupal/cms my-project
```

### Start-demo doesn't support --detached
If you get an error that `--detached` is not recognized:

**Check version:** The project may have an older version of the flake. Update with:
```bash
refresh-flake
# Or manually:
nix flake init -t /path/to/drupal-flake --refresh
```

**Workaround for older versions:**
```bash
export DEMO_DRUPAL_PACKAGE="drupal/cms"
export DEMO_RECIPE="recipes/byte"
start-detached
```

## Decision Tree for Agents

**Full Workflow for Any Drupal Project:**

```
1. Check if this is a NEW project (no code, no .env)
   Run: ls web/index.php 2>/dev/null || ls docroot/index.php 2>/dev/null
   AND: cat .env 2>/dev/null | grep PROJECT_NAME
   
    If NO code AND NO .env → NEW PROJECT:
      a. Check for flake.nix (ls flake.nix)
         NO → Run: nix flake init -t /path/to/drupal-flake
      b. **CRITICAL: Initialize git BEFORE starting services**
         ```bash
         git init
         git add flake.nix flake.lock .env .envrc .gitignore .services/
         # Note: 'git add' is sufficient - Nix uses staged files, commit is optional
         ```
         ⚠️ Without git, MySQL socket will cause Nix to fail!
      c. PROMPT USER (don't assume):
         - "Project name? (default: $(basename $PWD))"
         - "Port? (suggested: $(suggest_port), verify with: lsof -i :PORT)"  
         - "PHP version? (default: php84, options: php74/php83/php84)"
         - "Starting point? (1=Drupal CMS with byte recipe, 2=Commerce, 3=Vanilla)"
      d. Create .env file with user CONFIRMED values
      e. Determine package and recipe:
         - Choice 1 → drupal/cms, DEMO_RECIPE="recipes/byte"
         - Choice 2 → drupalcommerce/commerce_kickstart
         - Choice 3 → drupal/recommended-project
      f. Enter nix shell: nix develop (or wait for direnv)
      g. Set DEMO_RECIPE if needed, run: start-demo --detached [pkg] [name]
      h. WAIT FOR HTTP 200 (not process count!):
         - Poll: curl -s -o /dev/null -w "%{http_code}" [URL]
         - Expect "3/7 running" or "4/7 running" - setup processes COMPLETE and exit!
         - Success = HTTP 200 response, not "all processes running"
      i. Get credentials: drush uli, report success
      
2. EXISTING PROJECT - Check environment
   a. Is pc-status available and showing "running"?
      YES → Use drupal-flake, extract URL from .env, proceed
      NO → Continue
      
   b. Is ddev installed and showing "running" in ddev describe?
      YES → Use DDev, get URL from ddev describe  
      NO → Continue
      
   c. Are there Docker containers with PHP/Nginx/Apache running?
      YES → Use Docker, extract ports, construct URL
      NO → Continue
      
   d. No environment detected:
      Ask: "Would you like me to start drupal-flake?"
      YES → Run start-detached → wait for HTTP 200 → proceed
      NO → Ask which environment to use or manual setup
```

**⚠️ CRITICAL: Correct Completion Detection**

```bash
# WRONG - Don't do this:
until pc-status | grep -q "running and ready"; do sleep 5; done
# This waits for all processes, but setup processes are SUPPOSED to exit!

# CORRECT - Check HTTP response:
export URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
until curl -s -o /dev/null -w "%{http_code}" "$URL" | grep -q "200"; do
  echo "Waiting for $URL to respond..."
  sleep 10
done
echo "✅ Site is up!"

# Setup processes that complete (NORMAL behavior):
# - cms: completes after Drupal install
# - nix-settings: completes after writing settings.php
# - init: completes after initial setup
# 
# Persistent services that stay running:
# - php-fpm (PHP processor)
# - nginx (web server)
# - mysql (database)
# 
# Result: "3/7 running" means SUCCESS, not failure!
```

**Quick Check Commands:**
```bash
# New project detection
if [ ! -f "web/index.php" ] && [ ! -f "docroot/index.php" ] && [ ! -f ".env" ]; then
  echo "NEW PROJECT: Need to initialize"
fi

# Environment detection
echo "Checking environments..."
pc-status 2>/dev/null && echo "✓ drupal-flake running"
which ddev && ddev describe 2>/dev/null | grep -q "RUNNING" && echo "✓ DDev running"  
which docker && docker ps 2>/dev/null | grep -qE "(php|nginx|apache)" && echo "✓ Docker running"
```

## Important Notes

- **Git is REQUIRED** - `git init` immediately after `nix flake init`, BEFORE starting services
- **Never auto-start DDev** - it may conflict with user's intent
- **Always check HTTP 200 first** - Site responding is the TRUE success metric
- **Process count is misleading** - "3/7 running" is SUCCESS after setup completes
- **Setup processes are supposed to exit** - cms, nix-settings, init complete and exit (this is NORMAL)
- **Use start-detached over nix run** - doesn't block the agent
- **Wait for HTTP response** - not "all processes running" (setup processes complete!)
- **Respect .env configuration** - especially PORT and DOMAIN
- **Always PROMPT user** - don't use defaults without asking (project name, port, etc.)
- **Background vs Interactive** - `start-detached` is better for agents; `nix run` for user TUI
- **Get credentials via drush uli** - Don't wait for install output, generate fresh login link
- **MySQL socket causes Nix failures without git** - Socket files in data/ can't be tracked
