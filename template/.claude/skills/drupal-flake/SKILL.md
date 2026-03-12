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
- `start-demo [package] [name] [options]` - Create new Drupal site (all-in-one)
  - Examples:
    - `start-demo` - Default drupal/cms
    - `start-demo drupal/recommended-project my-site`
    - `start-demo phenaproxima/xb-demo xb-site --stability=dev`
- **Discrete Installation Steps** (for granular control and debugging):
  - `drupal-download [package] [directory] [options]` - Download Drupal via composer create-project
    - Supports `DEMO_STABILITY` environment variable (dev, alpha, beta, RC, stable)
    - Creates data/ directory automatically to avoid race conditions
    - Example: `DEMO_STABILITY=dev drupal-download drupal/cms`
  - `drupal-recipe <recipe-package>` - Install site template via composer
    - Handles stability adjustments automatically
    - Adds Drupal packages repository if needed
    - Example: `DEMO_STABILITY=dev drupal-recipe drupal/haven`
  - `drupal-install [recipe-or-profile]` - Run site installation with proper setup
    - Detects drush location (vendor/bin/ or bin/)
    - Handles settings.php permissions and nix-settings.php
    - Removes duplicate database config after install
    - Example: `drupal-install recipes/haven` or `drupal-install standard`
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

**Option 1b: Discrete Installation Steps** (for debugging/recovery)

When `start-demo` fails or you need more control, use the discrete commands:

```bash
# Step 1: Download Drupal package
DEMO_STABILITY=dev drupal-download drupal/cms

# Step 2: Install site template (if using one like Haven)
DEMO_STABILITY=dev drupal-recipe drupal/haven

# Step 3: Start the environment and install
dev
start-detached
# Wait for services to be ready
drupal-install recipes/haven
```

**Using discrete commands with custom site templates:**

```bash
# Download base Drupal
drupal-download drupal/cms

# Install the site template package (handles stability issues)
export DEMO_STABILITY=dev
drupal-recipe drupal/haven

# Find the recipe path
ls recipes/haven/recipe.yml

# Install the site
drupal-install recipes/haven
```

**Advantages of discrete commands:**
- Each step logs to separate files (data/download.log, data/recipe.log, data/install.log)
- Can retry failed steps without re-downloading
- Better error messages and recovery options
- Can inspect state between steps

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

**1. Initialize Git Repository and .gitignore (CRITICAL to prevent Nix errors)**

⚠️ **Without git and proper .gitignore, Nix will fail when MySQL starts** because it creates socket files that Nix can't handle during directory scanning.

**Step A: Check/Create .gitignore**

```bash
# Check if .gitignore exists
if [ -f ".gitignore" ]; then
  # Add data/ if not already present
  if ! grep -q "^data/$" .gitignore; then
    echo "" >> .gitignore
    echo "# Drupal-flake: ignore data directory (MySQL, logs, sockets)" >> .gitignore
    echo "data/" >> .gitignore
    echo "Added 'data/' to existing .gitignore"
  fi
else
  # No .gitignore - create one with sensible defaults for Drupal
  cat > .gitignore << 'GITIGNORE'
# Drupal-flake: data directory (MySQL, logs, sockets)
data/
*.sock

# Drupal site files and local environment settings
web/sites/*/files/
web/sites/*/private/
web/sites/*/translations/
# Ignore ALL environment-specific settings files (local, nix, ddev, etc.)
# except for the main settings.php which should be committed
web/sites/*/settings.*.php
!web/sites/*/settings.php
web/sites/simpletest/

# Composer
/vendor/
composer.lock

# Node.js
node_modules/
npm-debug.log
yarn-error.log

# IDEs and editors
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store

# Logs
*.log
logs/

# OS files
Thumbs.db
GITIGNORE
  echo "Created .gitignore with Drupal defaults"
fi
```

**Step B: Initialize git**

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
- The `data/` directory contains MySQL sockets that Nix cannot process
- Without git, Nix scans all files and fails on the socket file with "unsupported type" error
- Without git, changes to `.env` won't be picked up properly
- **Only `git add` is needed** - Nix evaluates based on staged files, not commits

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
   
   **Port Generation Algorithm:** Creates unique ports from project names
   
   ```bash
   suggest_port() {
     local name="${1:-$(basename "$PWD")}"
     local port=""
     local checksum=0
     local count=0
     
     # Convert to lowercase
     name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
     
     # Method 1: Use first 4 letters with telephone keypad (ABC=2, DEF=3, etc.)
     for (( i=0; i<${#name} && count<4; i++ )); do
       local char="${name:$i:1}"
       local digit=""
       
       case "$char" in
         [abc]) digit="2" ;;
         [def]) digit="3" ;;
         [ghi]) digit="4" ;;
         [jkl]) digit="5" ;;
         [mno]) digit="6" ;;
         [pqrs]) digit="7" ;;
         [tuv]) digit="8" ;;
         [wxyz]) digit="9" ;;
       esac
       
       if [ -n "$digit" ]; then
         port="${port}${digit}"
         ((count++))
       fi
     done
     
     # Method 2: Add uniqueness by incorporating name length and position
     # This ensures "cms" (3 letters) and "core" (4 letters) get different ports
     local len=${#name}
     local extra_digit=$(( (len % 8) + 2 ))  # 2-9 based on name length
     
     # Build final port: first 3 digits from name, 4th from length-based calculation
     if [ ${#port} -ge 3 ]; then
       port="${port:0:3}${extra_digit}"
     else
       # Pad with calculated digits if name is short
       while [ ${#port} -lt 3 ]; do
         port="${port}${port: -1}"
       done
       port="${port}${extra_digit}"
     fi
     
     # Ensure valid 4-digit port (2000-9999)
     if [ "${port:0:1}" = "1" ]; then
       port="2${port:1}"
     fi
     
     echo "$port"
   }
   
   # Better examples with uniqueness:
   # "cms"   → c=2, m=6, s=7, len=3 → extra=5 → 2675
   # "core"  → c=2, o=6, r=7, e=3, len=4 → extra=6 → 2676
   # "drupal" → d=3, r=7, u=8, p=7, len=6 → extra=8 → 3788
   # "freelock" → f=3, r=7, e=3, e=3, len=8 → extra=2 → 3732
   ```
   
   **Why this is better:**
   - Uses name length to add uniqueness (3-letter vs 4-letter names get different last digits)
   - Still based on phone keypad for memorability
   - "cms" (2675) and "core" (2676) are now adjacent but distinct
   - Falls within valid port range 2000-9999
   
   **Check availability:**
   ```bash
   PORT=$(suggest_port "cms")
   if lsof -i :$PORT >/dev/null 2>&1; then
     echo "Port $PORT is in use, trying $((PORT + 1))..."
   fi
   ```
   ABC = 2    DEF = 3    GHI = 4
   JKL = 5    MNO = 6    PQRS = 7
   TUV = 8    WXYZ = 9
   ```
   
   **Examples:**
   - `cms` → c=2, m=6, s=7 → **2677** (add last digit to make 4 digits)
   - `drupal` → d=3, r=7, u=8, p=7 → **3787**
   - `freelock` → f=3, r=7, e=3, l=5 → **3735**
   
   **Working port suggestion script:**
   ```bash
   suggest_port() {
     local name="${1:-$(basename "$PWD")}"
     local port=""
     local count=0
     
     # Convert to lowercase and iterate through characters
     name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
     
     for (( i=0; i<${#name}; i++ ));
     do
       local char="${name:$i:1}"
       local digit=""
       
       case "$char" in
         [abc]) digit="2" ;;      # ABC = 2
         [def]) digit="3" ;;      # DEF = 3
         [ghi]) digit="4" ;;      # GHI = 4
         [jkl]) digit="5" ;;      # JKL = 5
         [mno]) digit="6" ;;      # MNO = 6
         [pqrs]) digit="7" ;;     # PQRS = 7
         [tuv]) digit="8" ;;      # TUV = 8
         [wxyz]) digit="9" ;;     # WXYZ = 9
       esac
       
       if [ -n "$digit" ]; then
         port="${port}${digit}"
         ((count++))
       fi
       
       # Build 4-digit port from first 4 letters
       if [ $count -eq 4 ]; then
         break
       fi
     done
     
     # If we have less than 4 digits, repeat the last digit
     while [ ${#port} -lt 4 ]; do
       port="${port}${port: -1}"
     done
     
     echo "$port"
   }
   
   # Examples:
   # suggest_port "cms"    → 2677
   # suggest_port "drupal" → 3787
   # suggest_port "freelock" → 3735
   ```
   
   **Port range:** 1024-65535 (most 4-digit ports 2000-9999 work well)
   
   **Check availability:**
   ```bash
   PORT=$(suggest_port "cms")
   if lsof -i :$PORT >/dev/null 2>&1; then
     echo "Port $PORT is in use, trying $((PORT + 1))..."
   fi
   ```

3. **PHP Version**
   - Options: `php74`, `php83`, `php84` (default: `php84`)
   - Note: php74 requires legacy nixpkgs, others use standard

4. **Starting Point** (Drupal Distribution)
   - **Drupal CMS 2.0** → `drupal/cms` (latest, includes modern features)
   - **Drupal Commerce Kickstart** → `centarro/commerce-kickstart-project` (creates `kickstart/` dir)
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
| Commerce Kickstart | `centarro/commerce-kickstart-project` | Standard install, creates `kickstart/` directory |
| Vanilla Core | `drupal/recommended-project` | Installs drush, then `drush site:install standard` |
| Custom | User-provided | Ask user for install command |

**Note on Directory Names:** Different packages create different directories:
- `drupal/cms` → creates `cms/` directory
- `centarro/commerce-kickstart-project` → creates `kickstart/` directory  
- `drupal/recommended-project` → creates the project name directory

**Note on Binary Locations:** Different packages put binaries in different places:
- Most packages → `vendor/bin/drush`
- Commerce Kickstart → `bin/drush` (custom `bin-dir` in composer.json)

The init script and xdrush wrapper handle both locations automatically.

The init script automatically detects and handles this - you don't need to manually move files.

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
   
2. **CRITICAL: Initialize git and .gitignore BEFORE doing anything else**
   ```bash
   # Step A: Handle .gitignore
   if [ ! -f ".gitignore" ]; then
      # Create new .gitignore with Drupal defaults
      cat > .gitignore << 'EOF'
# Drupal-flake: data directory (MySQL, logs, sockets)
data/
*.sock

# Drupal site files and local settings
web/sites/*/files/
web/sites/*/settings.*.php
!web/sites/*/settings.php
web/sites/*/private/

vendor/
node_modules/
EOF
     echo "Created .gitignore"
    elif ! grep -q "^data/$" .gitignore; then
      # Add to existing .gitignore
      echo -e "\n# Drupal-flake
data/" >> .gitignore
      echo "Added 'data/' to .gitignore"
    fi
    
    # Also ensure settings.*.php is excluded (for nix, ddev, local settings)
    if ! grep -q "settings\.\*\.php" .gitignore 2>/dev/null; then
      echo -e "\n# Ignore environment-specific settings (nix, ddev, local)\nweb/sites/*/settings.*.php\n!web/sites/*/settings.php" >> .gitignore
      echo "Added settings pattern to .gitignore"
    fi
   
   # Step B: Initialize git
   git init
   git add flake.nix flake.lock .env .envrc .gitignore .services/
   # Note: git add is sufficient - Nix uses staged files, user can commit later
   ```
   
   ⚠️ **If you skip this:** MySQL socket will cause Nix to fail!
   
3. Check if .env exists AND web/index.php exists
   YES → Existing project, skip to environment detection
   NO  → Continue with initialization
   
4. **CRITICAL - MUST PROMPT USER:** 
   
   ⚠️ **DO NOT SKIP THESE QUESTIONS - DO NOT USE DEFAULTS WITHOUT ASKING!**
   
   Common agent mistake: Using the directory name as project name and 8080 as port without asking. **This is WRONG!**
   
   **YOU MUST ASK ALL 4 QUESTIONS EXPLICITLY:**
   
   **DO:**
   - Ask: "What project name should I use? (detected directory: 'cms')"
   - Ask: "What port should I use? (calculated from 'cms': 2677, or would you prefer 8080?)"
   - Ask: "Which PHP version? (options: php74, php83, php84 - default: php84)"
   - Ask: "Which starting point? 1) Drupal CMS with byte recipe, 2) Commerce Kickstart, 3) Vanilla core"
   - Wait for user to respond to EACH question before proceeding
   
   **DON'T:**
   - Assume project name = directory name
   - Assume port = 8080 or any default
   - Assume PHP version = php84
   - Assume starting point = Drupal CMS
   - Proceed to create .env until ALL 4 questions are answered
   
   **Template for asking:**
   ```
   I'm setting up a new Drupal project. I need to ask you 4 quick questions:
   
   1. Project name? (detected: 'cms')
   2. HTTP port? (calculated: 2677 from 'cms', or choose 8080, 8888, etc.)
   3. PHP version? (php84 recommended, or php74/php83)
   4. Starting point?
      - Drupal CMS 2.0 with full demo content (byte recipe, ~3-5 min)
      - Commerce Kickstart (e-commerce setup)
      - Vanilla Drupal core (minimal, ~1-2 min)
   
   What are your preferences?
   ```
   
   **Verification:**
   After user responds, confirm back: "Got it: project='cms', port=2677, php=php84, starting with Drupal CMS. Creating .env now..."
   
   **If user doesn't specify:**
   - Project: Ask again "What project name should I use?"
   - Port: Ask again "What port? The calculated port 2677 is available."
   - PHP: Use php84 but confirm "Using php84 - is that okay?"
   - Starting point: Ask again "Which option 1, 2, or 3?"
   
   a. **Project name?**
      - Check: basename "$PWD" → e.g., "cms"
      - Suggest: "What project name should I use? (default: cms)"
      - Wait for user confirmation or input
   
    b. **Port?** 
       - Calculate: Using phone keypad + name length for uniqueness
       - For "cms" (3 letters): 2+6+7 + len-based 5 → **2675**
       - For "core" (4 letters): 2+6+7 + len-based 6 → **2676** (different from cms!)
       - Suggest: "What port should I use? (calculated from 'cms': 2675, verify with: lsof -i :2675)"
       - Wait for user confirmation or input
       - Alternative: Offer standard ports like 8080, 8888, or their calculated port
   
   c. **PHP version?**
      - Suggest: "Which PHP version? (default: php84, options: php74, php83, php84)"
      - Wait for user confirmation
   
   d. **Starting point?**
      - Explain: "Drupal CMS 2.0 includes full demo content via 'byte' recipe (~3-5 min install). Vanilla is minimal Drupal core (~1-2 min)."
      - Options: "1) Drupal CMS 2.0 (full demo), 2) Commerce Kickstart (e-commerce), 3) Vanilla core (minimal)"
      - Wait for user selection

4. Write .env file with CONFIRMED user selections
   
5. **Add .env to git (critical for Nix to see it):**
   ```bash
   git add .env .gitignore
   # Re-stage to ensure Nix sees the updated .env with correct project name
   ```
   
6. Determine package and recipe based on user choice:
   - Choice 1 (CMS) → drupal/cms + DEMO_RECIPE="recipes/byte"
   - Choice 2 (Commerce) → centarro/commerce-kickstart-project + no recipe
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

**Problem:** The agent created `.env` without asking the user for:
- Project name (used directory name instead)
- Port (used 8080 instead of calculated port like 2677)
- PHP version (assumed php84)
- Starting point (assumed Drupal CMS)

**This is WRONG** - The agent MUST ask ALL 4 questions and wait for answers.

**Why this happens:**
- Agent thinks defaults are "good enough"
- Agent tries to be efficient by skipping "unnecessary" questions
- Agent doesn't realize user might want custom values

**PREVENTION - What agents MUST do:**

```bash
# BEFORE creating .env, ask ALL 4 questions:

1. Project name:
   DEFAULT=$(basename "$PWD")
   Ask: "What project name should I use? (detected: '$DEFAULT')"
   # Wait for user response - do not assume

2. Port:
   PORT=$(suggest_port "$DEFAULT")  # e.g., 2677 for "cms"
   Ask: "What port should I use? (calculated from '$DEFAULT': $PORT)"
   # Wait for user response - offer alternatives like 8080, 8888

3. PHP version:
   Ask: "Which PHP version? (default: php84, options: php74, php83, php84)"
   # Wait for user response - don't assume php84

4. Starting point:
   Ask: "Which starting point?
   1) Drupal CMS 2.0 with full demo content (recipes/byte, ~3-5 min)
   2) Commerce Kickstart (e-commerce setup)
   3) Vanilla Drupal core (minimal, ~1-2 min)"
   # Wait for user selection - don't assume option 1

# Confirm back to user:
"Got it! Using: project='$PROJECT', port=$PORT, php=$PHP, starting with $STARTING_POINT"

# Only NOW create .env:
# ⚠️ IMPORTANT: Do NOT add SITE_NAME or other optional variables
# If you must add values with spaces, quote them properly: SITE_NAME="Commerce Kickstart"
cat > .env << EOF
PROJECT_NAME=$PROJECT
DOMAIN=${PROJECT}.ddev.site
PORT=$PORT
PHP_VERSION=$PHP
DOCROOT=web
EOF
```

**RECOVERY - If wrong config was created:**
```bash
# Stop everything
stop-all

# Remove incorrect data
rm -rf data/ web/ .env

# Remove from git
git rm -f --cached .env 2>/dev/null || true

# Start over and ask ALL questions this time
```

**Agent Self-Check:**
Before creating `.env`, verify:
- [ ] Did I ask for project name? (not assume basename $PWD)
- [ ] Did I ask for port? (not assume 8080)
- [ ] Did I ask for PHP version? (not assume php84)
- [ ] Did I ask for starting point? (not assume CMS)
- [ ] Did I wait for user response to each question?
- [ ] Did I confirm the choices with the user?

If any answer is NO, go back and ask the question!

### .env file format errors / dotenv library failures

**Problem:** Installation fails with dotenv library errors:
```
dotenv: Error parsing .env file at line X: SITE_NAME=Commerce Kickstart
```

**Cause:** Values with spaces are not quoted, or extra variables were added.

**Root causes:**
1. **Spaces without quotes:** `SITE_NAME=Commerce Kickstart` breaks dotenv parsers
2. **Agent adding extra variables:** The agent shouldn't add SITE_NAME or other optional vars
3. **Values containing special characters:** `#`, `=`, `:` can break parsing

**Solution:**

```bash
# Proper .env file format:
# - NO spaces around =
# - Quote values with spaces: KEY="value with spaces"
# - Don't add optional variables unless necessary

# WRONG:
SITE_NAME=Commerce Kickstart           # Breaks: space without quotes
SITE_NAME = "Commerce Kickstart"       # Breaks: space around =

# CORRECT:
PROJECT_NAME=kickstart                 # OK: no spaces
SITE_NAME="Commerce Kickstart"       # OK: quoted value
```

**Prevention:**
- Only set: PROJECT_NAME, DOMAIN, PORT, PHP_VERSION, DOCROOT
- Don't add: SITE_NAME, ADMIN_NAME, or other variables
- If you must add SITE_NAME, use quotes: `SITE_NAME="My Site"`
- Never put spaces around the `=` sign

**Fix broken .env:**
```bash
# Check current .env
cat .env

# Fix by rewriting with proper format
cat > .env << 'EOF'
PROJECT_NAME=kickstart
DOMAIN=kickstart.ddev.site
PORT=5454
PHP_VERSION=php84
DOCROOT=web
EOF
```

### Agent prompting issues - Inconsistent interfaces

**Problem:** Agent sometimes uses nice tabbed/picker interface, sometimes just lists defaults as text.

**Expected behavior:** Agent should use consistent interactive prompts (arrow keys + enter) for all questions.

**Inconsistent examples:**
```
# BAD - Just listing text:
"Project name? (detected: cms)"
"Port? (2675)"  
"PHP version? (php84)"
"Starting point? (1=CMS, 2=Commerce, 3=Vanilla)"
# User has to type everything manually

# GOOD - Interactive picker with arrow keys:
? Project name: (cms) › 
? Port: (Use arrow keys)
  2675 (calculated)
  8080
  8888
❯ 2675
```

**Required prompting method:**
1. Use interactive pickers with arrow key navigation for ALL questions
2. Show calculated/suggested values as the default (highlighted)
3. Allow user to either:
   - Press Enter to accept default
   - Type a custom value
   - Use arrow keys to select from options

**Implementation:**
```
Question format for each prompt:
1. "Project name? (detected: 'cms')" 
   - Show default from directory name
   - Allow typing custom name
   
2. "Port? (calculated: 2675)"
   - Show calculated port
   - Offer alternatives: 8080, 8888
   
3. "PHP version? (default: php84)"
   - Show options: php74, php83, php84
   
4. "Starting point?"
   - Option 1: Drupal CMS (full demo)
   - Option 2: Commerce Kickstart
   - Option 3: Vanilla core
```

**If agent is not using interactive prompts:**
Remind the agent: "Please use interactive pickers with arrow keys for all questions, not just listing them as text."

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

### Commerce Kickstart installation issues

**Problem 1:** Composer dependency errors during installation:
```
centarro/commerce_kickstart requires drupal/commerce_kickstart_base ^1 -> could not be found
```

**Solution:** Run composer update after the initial install:
```bash
cd /path/to/kickstart
composer update
```

**Problem 2:** Drush not found - `vendor/bin/drush` doesn't exist

**Cause:** Commerce Kickstart uses a custom `bin-dir: bin` in composer.json, so binaries are in `bin/` not `vendor/bin/`.

**Solution:** Use `bin/drush` instead:
```bash
./bin/drush site:install commerce_kickstart_demo
./bin/drush cache:rebuild
```

Or if drush command not found, check both locations:
```bash
# For most projects:
vendor/bin/drush status

# For Commerce Kickstart:
bin/drush status
```

**Problem 3:** Site loads with errors after installation

**Solution:** Clear caches and run the kickstart recipe:
```bash
# Install the demo content
./bin/drush site:install commerce_kickstart_demo

# Clear all caches
./bin/drush cache:rebuild
```

### Vanilla Core (drupal/recommended-project) installation issues

**Problem 1:** Drush not found during installation

**Cause:** Vanilla core doesn't include drush by default, unlike CMS or Kickstart.

**Solution:** The init script now automatically installs drush if missing. If you hit this issue manually:
```bash
composer require drush/drush --with-all-dependencies
```

**Problem 2:** Settings.php gets corrupted

**Cause:** `drush site:install` adds a database configuration block to the end of settings.php, which conflicts with our nix-settings.php configuration.

**Current behavior:** The init script:
1. Creates settings.php from default.settings.php
2. Runs nix-settings (creates settings.nix.php with database config)
3. Backs up settings.php
4. Runs drush site:install (adds $databases to settings.php)
5. Restores the backup (removes drush's database block)

This should work automatically. If you see database errors:
```bash
# Check that settings.nix.php exists
ls web/sites/default/settings.nix.php

# If missing, regenerate it
nix-settings [project-name] web [path-to-mysql-sock]

# Clear caches
drush cache:rebuild
```

**Problem 3:** Site shows errors after installation

**Solution:** Always clear caches after installation:
```bash
drush cache:rebuild
# or
drush cr
```

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
**Error:** `error: file '/path/to/data/PROJECT-db/mysql.sock' has an unsupported type`

**Root Cause:** Nix cannot handle socket files when evaluating the flake. MySQL creates `mysql.sock` in the `data/` directory. Without git or without `data/` in `.gitignore`, Nix sees the socket and fails.

**Solutions (in order of preference):**

**Option 1: Ensure .gitignore and git are properly configured (BEST)**
```bash
# Check if data/ is in .gitignore
grep -q "^data/$" .gitignore 2>/dev/null || echo "data/" >> .gitignore

# Remove existing socket files
rm -f data/*/mysql.sock

# Make sure files are added to git
git add .gitignore flake.nix flake.lock .env .envrc .services/

# Now nix commands will work
nix flake update
```

**Option 2: Remove socket files and use --impure**
```bash
# Stop the environment first
stop-all 2>/dev/null || true

# Remove socket files
rm -f data/*/mysql.sock

# Use --impure flag (works but not ideal)
nix develop --impure
```

**Prevention:**
- Always ensure `.gitignore` includes `data/` before running any nix commands
- Initialize git immediately after `nix flake init`
- The combination of git + .gitignore prevents Nix from seeing the socket

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

## Installation Failure Recovery

When installation fails, it's critical to properly clean up before retrying. Partially started services can cause conflicts and prevent successful retries.

### Step 1: Stop All Services on Failure

**ALWAYS run `pc-stop` when any installation step fails:**

```bash
# Stop all process-compose services for this project
pc-stop

# Or stop ALL process-compose environments (if pc-stop doesn't work)
stop-all
```

**Why this matters:**
- MySQL may have partially initialized and have corrupted data
- PHP-FPM may have cached bad configuration
- Nginx may have open connections to broken upstreams
- Files may be locked by running processes

### Step 2: Check for Partial State

```bash
# Look for leftover processes
pc-status

# Check for data directory issues
ls -la data/

# Look for lock files or sockets
find . -name "*.sock" -o -name "*.lock" 2>/dev/null | grep -v node_modules
```

### Step 3: Clean Up Failed State (if needed)

**If the failure was during initial Drupal download/install:**
```bash
# Remove partially downloaded Drupal
rm -rf web/ vendor/ composer.lock

# Clear data directory (WARNING: destroys database)
rm -rf data/

# Restart from clean state
start-detached
```

**If database is corrupted:**
```bash
# Nuclear option: wipe everything and start fresh
pc-stop
rm -rf data/
start-detached
```

### Step 4: Use Discrete Commands for Recovery

When `start-demo` keeps failing, switch to **discrete commands** for better control and debugging:

**The discrete command workflow:**

```bash
# 1. Stop any running services
pc-stop

# 2. Clean up partial state (if needed)
rm -rf web/ vendor/ composer.lock data/*

# 3. Download Drupal with explicit stability
cd /path/to/project
export DEMO_STABILITY=dev
drupal-download drupal/cms 2>&1 | tee data/download.log

# 4. If using a site template, install it
export DEMO_RECIPE=recipes/haven
drupal-recipe drupal/haven 2>&1 | tee data/recipe.log

# 5. Start services
start-detached

# 6. Install the site
drupal-install recipes/haven 2>&1 | tee data/install.log
```

**Benefits of discrete commands:**
- **Separate logs** for each step: `data/download.log`, `data/recipe.log`, `data/install.log`
- **Retry individual steps** without re-downloading everything
- **Better error messages** - each command focuses on one task
- **Manual inspection** between steps

**Common recovery scenarios:**

**Scenario: Download fails due to stability**
```bash
# Error: Your requirements could not be resolved to an installable set
# Solution: Use DEMO_STABILITY=dev
DEMO_STABILITY=dev drupal-download drupal/cms
```

**Scenario: Recipe package not found**
```bash
# Error: Could not find package drupal/haven
# Solution: drupal-recipe adds repositories automatically
drupal-recipe drupal/haven
```

**Scenario: Missing modules during install**
```bash
# Error: Module 'webform' not found during drupal-install
# Solution: Check log and install manually
MISSING=$(grep -oE "Module ['\"]?[a-z_]+['\"]? not found" data/install.log | head -1)
composer require drupal/webform --with-all-dependencies
# Then retry
drupal-install recipes/haven
```

**Scenario: Race condition with data/ directory**
```bash
# Error: data/ directory doesn't exist when trying to log
# Solution: Create data directory BEFORE starting
mkdir -p data
drupal-download drupal/cms  # This now creates data/ automatically
```

### Installation Monitoring with Automatic Failure Detection

**Monitor installation logs and detect failures automatically:**

```bash
export LOG_FILE="data/demo-detached.log"
export BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"

# Monitor with failure detection
while true; do
  # Check if site is up (success)
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null)
  if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ SUCCESS! Site is responding at $BASE_URL"
    break
  fi
  
  # Check for composer failures
  if tail -20 "$LOG_FILE" 2>/dev/null | grep -qE "(Your requirements could not be resolved|Installation failed|composer error|Could not find package|stability.*dev)"; then
    echo "❌ COMPOSER FAILURE DETECTED"
    echo "Recent log entries:"
    tail -30 "$LOG_FILE" | grep -E "(error|fail|require|constraint|stability)"
    
    # Stop everything
    pc-stop
    
    # Handle stability issues
    if tail -30 "$LOG_FILE" | grep -q "minimum-stability"; then
      echo "Stability issue detected - need to adjust composer requirements"
      # See "Handling Composer Failures" section below
    fi
    
    break
  fi
  
  # Check for PHP/drush errors
  if tail -20 "$LOG_FILE" 2>/dev/null | grep -qE "(PHP Fatal|Drush command failed|Could not find|Class.*not found)"; then
    echo "❌ INSTALLATION FAILURE DETECTED"
    echo "Recent errors:"
    tail -30 "$LOG_FILE" | grep -E "(Fatal|Error|failed|not found)"
    
    # Stop everything before retry
    pc-stop
    break
  fi
  
  echo "$(date '+%H:%M:%S'): Installing... (HTTP: $HTTP_STATUS)"
  sleep 10
done
```

## Handling Composer Failures

Composer failures during installation are common, especially with development versions or custom packages.

### Common Composer Errors

**Error 1: Minimum stability requirements**
```
Your requirements could not be resolved to an installable set of packages.
  Problem 1
    - Root package requires drupal/haven * -> satisfiable by drupal/haven[1.0.x-dev].
    - drupal/haven 1.0.x-dev requires composer/installers ^2.0 -> found composer/installers[2.0.0] but the package is fixed to 1.x.
```

**Error 2: Missing packages or repositories**
```
Could not find a matching version of package drupal/custom_module. 
Check the package spelling or your minimum-stability
```

**Error 3: Repository configuration**
```
Failed to download vendor/package from dist: The "https://..." file could not be downloaded (HTTP/1.1 404 Not Found)
```

### Resolution Steps

**Step 1: Stop the environment**
```bash
pc-stop
```

**Step 2: Check composer.json for issues**
```bash
# Check stability settings
cat composer.json | grep -A5 minimum-stability

# Check repositories section
cat composer.json | grep -A20 repositories

# Check required packages
cat composer.json | grep -A30 require
```

**Step 3: Fix stability issues**

If the package requires dev stability:
```bash
# Option A: Set minimum-stability to dev
composer config minimum-stability dev

# Option B: Add specific package with @dev flag
composer require drupal/package-name:@dev --no-update

# Then update
composer update
```

**Step 4: Fix repository issues**

If the package is in a custom repository:
```bash
# Add custom repository if needed
composer config repositories.custom vcs https://github.com/org/repo

# Or add Drupal packages repo if missing
composer config repositories.drupal composer https://packages.drupal.org/8
```

**Step 5: Clear composer cache and retry**
```bash
# Clear cache
composer clear-cache

# Remove lock file to regenerate
rm composer.lock

# Update with full dependencies
composer update --with-all-dependencies
```

**Step 6: Restart installation**
```bash
# After fixing composer issues
start-detached
```

### Automated Composer Failure Handler

```bash
handle_composer_failure() {
  local log_file="${1:-data/demo-detached.log}"
  
  echo "Checking for composer failures..."
  
  # Check for stability issues
  if grep -q "minimum-stability" "$log_file" 2>/dev/null; then
    echo "⚠️  Stability issue detected - setting minimum-stability to dev"
    composer config minimum-stability dev
    composer update --no-install 2>&1 | tee -a "$log_file"
    return 0
  fi
  
  # Check for missing packages
  if grep -q "Could not find.*package" "$log_file" 2>/dev/null; then
    echo "⚠️  Missing package detected - checking repositories"
    
    # Ensure Drupal packages repository is configured
    if ! composer config repositories.drupal 2>/dev/null; then
      echo "Adding Drupal packages repository..."
      composer config repositories.drupal composer https://packages.drupal.org/8
      composer update --no-install 2>&1 | tee -a "$log_file"
    fi
    return 0
  fi
  
  return 1
}

# Usage during installation monitoring
if tail -50 data/demo-detached.log | grep -q "requirements could not be resolved"; then
  pc-stop
  handle_composer_failure data/demo-detached.log
  start-detached
fi
```

## Site Template Installation (New Drupal Recipe Convention)

Drupal CMS 2.0+ no longer requires traditional installation profiles. Instead, it uses **site templates** - complete site configurations delivered as recipes that include:
- Configuration (content types, fields, views, etc.)
- Content (demo content, initial pages)
- Themes (custom themes bundled with the template)
- Dependencies (modules specified in the recipe)

### Site Template Structure

A site template (like "haven") typically has this structure:
```
recipes/haven/
├── recipe.yml              # Recipe manifest
├── config/                 # Configuration files
│   ├── core.entity_form_display.node.page.default.yml
│   ├── field.field.node.page.body.yml
│   └── ...
├── content/                # Default content
│   └── ...
├── files/                  # Asset files
│   └── ...
└── themes/                 # Bundled themes
    └── haven_theme/
```

### Installation Command

**For Haven site template:**
```bash
# Haven installs in recipes/haven/, Drupal core is in web/core/
# The relative path from web/sites/default is ../../recipes/haven
# Or from project root: drush site:install recipes/haven

drush site:install recipes/haven --yes
```

**General site template pattern:**
```bash
# Site templates install via relative path from Drupal root
drush site:install ../recipes/[template-name]
```

### Complete Site Template Installation Workflow

**Recommended Approach: Using Discrete Commands**

The easiest way to install a site template is using the discrete commands:

```bash
# Step 1: Download base Drupal (if not already done)
drupal-download drupal/cms

# Step 2: Install the site template package
# This handles stability settings and repository configuration
export DEMO_STABILITY=dev
drupal-recipe drupal/haven

# Step 3: Install the site
# This handles drush detection, settings.php setup, and cleanup
drupal-install recipes/haven
```

**Alternative: Manual composer approach**

If you need more control over the process:

```bash
# Step 1: Install the site template package
composer require drupal/haven --with-all-dependencies

# Or with stability adjustment
composer config minimum-stability dev
composer require drupal/haven --with-all-dependencies

# Or if it's a custom/private package
composer config repositories.haven vcs https://github.com/org/haven
composer require drupal/haven
```

**Step 2: Check for missing modules**

The site template recipe may specify required modules. Check if they're installed:
```bash
# List enabled modules
drush pm:list --type=module --status=enabled

# Check if specific module is enabled
drush pm:info module_name

# Or check for missing dependencies
drush site:install recipes/haven --yes 2>&1 | tee install.log
```

**Step 3: Handle missing module failures**

If the recipe installation fails due to missing modules:
```bash
# Using the discrete drupal-install command (auto-handles this):
# drupal-install will detect missing modules and suggest installation

# Or manually:
# Extract missing module names from error
MISSING_MODULES=$(grep -oE "Module [a-z_]+ not found" install.log | sed 's/Module //;s/ not found//' | sort -u)

# Install each missing module
for module in $MISSING_MODULES; do
  echo "Installing missing module: $module"
  composer require drupal/$module --with-all-dependencies
done

# Restart with pc-stop to ensure clean state
pc-stop
start-detached
```

**Automated missing module handler with discrete commands:**

```bash
# The drupal-install command includes retry logic
# If it fails with missing modules, run:

# Install missing modules manually
MISSING=$(grep -oE "Module ['\"]?[a-z_]+['\"]? not found" data/install.log | \
  sed -E "s/.*['\"]?([a-z_]+)['\"]?.*/\1/" | sort -u)
for module in $MISSING; do
  composer require drupal/$module --with-all-dependencies
done

# Then retry installation (pc-stop not needed between composer and drupal-install)
drupal-install recipes/haven
```

**Step 4: Verify recipe installation**

```bash
# Check that recipe was applied
drush config:get core.extension module | grep haven

# List enabled recipes (Drupal 10.3+)
drush recipe:list 2>/dev/null || echo "Recipe list command not available"

# Check for recipe content
ls -la recipes/haven/content/ 2>/dev/null
```

**Step 5: Clear caches and verify site**
```bash
drush cache:rebuild

# Check site responds
curl -s -o /dev/null -w "%{http_code}" "http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
```

### Site Template Troubleshooting

**Issue: Recipe not found**
```bash
# Check recipe exists at expected path
ls -la recipes/haven/recipe.yml

# Check recipe syntax
head -20 recipes/haven/recipe.yml
```

**Issue: Modules specified in recipe not installing**
- The recipe declares dependencies but composer must install them
- Use the automated handler above to detect and install missing modules
- Some modules may need manual installation if not on drupal.org

**Issue: Content not imported**
- Recipes may not auto-import content on installation
- Check if content exists: `drush content:list`
- Manually import if needed: `drush content:import recipes/haven/content/`

## File Permissions and Settings.php Management

File permission issues commonly cause installation failures or site errors after installation.

### Critical Permission Checks

**Step 1: Check web/sites/default directory permissions**
```bash
# The directory must be writable during installation
ls -ld web/sites/default

# Expected: drwxrwxrwx or drwxr-xr-x (writable)
# If not writable, fix:
chmod 755 web/sites/default
```

**Step 2: Check settings.php permissions**
```bash
# Check current permissions
ls -l web/sites/default/settings.php

# During installation: must be writable
chmod 644 web/sites/default/settings.php

# After installation: should be read-only for security
chmod 444 web/sites/default/settings.php
```

**Step 3: Verify settings.php content**

Common issue: Drush `site:install` appends a `$databases` array to the end of settings.php, which conflicts with `nix-settings.php` include.

```bash
# Check if settings.php has nix-settings include
grep -n "nix-settings" web/sites/default/settings.php

# Check if duplicate database config was appended (problem!)
tail -30 web/sites/default/settings.php | grep -A10 "databases"

# The file should end with the nix-settings include, NOT a databases array
```

### Settings.php Repair Workflow

**When settings.php gets corrupted with duplicate database config:**

```bash
repair_settings_php() {
  local settings_file="web/sites/default/settings.php"
  local backup_file="web/sites/default/settings.php.backup"
  
  echo "Checking settings.php for corruption..."
  
  # Backup current file
  cp "$settings_file" "$backup_file"
  
  # Check if drush appended database config (it comes after our include)
  if grep -n "^\$databases" "$settings_file" | tail -1 | grep -qE "^[0-9]+:"; then
    local db_line=$(grep -n "^\$databases" "$settings_file" | tail -1 | cut -d: -f1)
    local total_lines=$(wc -l < "$settings_file")
    
    echo "Found \$databases array at line $db_line (file has $total_lines lines)"
    
    # Check if nix-settings include comes before it
    local nix_line=$(grep -n "nix-settings.php" "$settings_file" | tail -1 | cut -d: -f1)
    
    if [ -n "$nix_line" ] && [ "$nix_line" -lt "$db_line" ]; then
      echo "❌ CORRUPTION DETECTED: \$databases array was appended after nix-settings include"
      echo "Removing duplicate database configuration..."
      
      # Remove everything after nix-settings.php line
      head -n "$nix_line" "$settings_file" > "${settings_file}.tmp"
      mv "${settings_file}.tmp" "$settings_file"
      
      # Ensure proper ending
      echo "" >> "$settings_file"
      
      echo "✅ Repaired settings.php - removed duplicate database config"
    fi
  fi
  
  # Verify nix-settings.php exists and is included
  if [ ! -f "web/sites/default/settings.nix.php" ]; then
    echo "⚠️  settings.nix.php missing - regenerating..."
    nix-settings $(grep PROJECT_NAME .env | cut -d= -f2) web "$(ls data/*-db/mysql.sock 2>/dev/null | head -1)"
  fi
  
  # Fix permissions
  chmod 644 "$settings_file"
  
  # Verify the include is present
  if ! grep -q "settings.nix.php" "$settings_file"; then
    echo "Adding nix-settings.php include..."
    echo "require_once __DIR__ . '/settings.nix.php';" >> "$settings_file"
  fi
}

# Usage after detecting database connection issues
repair_settings_php
```

### Pre-Installation Permission Setup

**Always run this before `drush site:install`:**

```bash
prepare_for_install() {
  echo "Preparing file permissions for installation..."
  
  # Ensure sites/default is writable
  if [ -d "web/sites/default" ]; then
    chmod 755 web/sites/default
    echo "✓ web/sites/default is writable"
  else
    mkdir -p web/sites/default
    chmod 755 web/sites/default
    echo "✓ Created web/sites/default"
  fi
  
  # Create settings.php if it doesn't exist
  if [ ! -f "web/sites/default/settings.php" ]; then
    if [ -f "web/sites/default/default.settings.php" ]; then
      cp web/sites/default/default.settings.php web/sites/default/settings.php
      echo "✓ Created settings.php from default.settings.php"
    fi
  fi
  
  # Ensure settings.php is writable for installation
  if [ -f "web/sites/default/settings.php" ]; then
    chmod 644 web/sites/default/settings.php
    echo "✓ settings.php is writable"
  fi
  
  # Ensure nix-settings.php will be created and included
  if [ ! -f "web/sites/default/settings.nix.php" ]; then
    echo "Note: nix-settings.php will be generated during installation"
  fi
}

# Usage before site:install
prepare_for_install
drush site:install recipes/haven --yes
```

### Post-Installation Permission Lockdown

**Secure the site after successful installation:**

```bash
secure_installation() {
  echo "Securing file permissions..."
  
  # Make settings.php read-only
  if [ -f "web/sites/default/settings.php" ]; then
    chmod 444 web/sites/default/settings.php
    echo "✓ settings.php is now read-only (444)"
  fi
  
  # Keep sites/default accessible but not writable by all
  chmod 755 web/sites/default
  
  # Secure any other sensitive files
  if [ -f "web/sites/default/settings.nix.php" ]; then
    chmod 444 web/sites/default/settings.nix.php
  fi
}

# Usage after successful install
secure_installation
```

### Complete Installation Checklist

Before running `drush site:install`, verify:

```bash
pre_install_checklist() {
  local errors=0
  
  echo "=== Pre-Installation Checklist ==="
  
  # 1. Services running
  if ! pc-status | grep -q "running"; then
    echo "❌ Services not running - start with: start-detached"
    ((errors++))
  else
    echo "✓ Services are running"
  fi
  
  # 2. Database accessible
  if [ ! -S "data/$(grep PROJECT_NAME .env | cut -d= -f2)-db/mysql.sock" 2>/dev/null ]; then
    echo "⚠️  MySQL socket not found - may still be starting"
  else
    echo "✓ MySQL socket exists"
  fi
  
  # 3. sites/default exists and is writable
  if [ ! -d "web/sites/default" ]; then
    mkdir -p web/sites/default
    echo "✓ Created web/sites/default"
  fi
  
  if [ ! -w "web/sites/default" ]; then
    chmod 755 web/sites/default
    echo "✓ Made web/sites/default writable"
  fi
  
  # 4. settings.php exists and is writable
  if [ ! -f "web/sites/default/settings.php" ]; then
    if [ -f "web/sites/default/default.settings.php" ]; then
      cp web/sites/default/default.settings.php web/sites/default/settings.php
      echo "✓ Created settings.php"
    fi
  fi
  
  if [ -f "web/sites/default/settings.php" ]; then
    chmod 644 web/sites/default/settings.php
    echo "✓ settings.php is writable"
  fi
  
  # 5. No conflicting database config
  if grep -q "^\$databases.*=.*\[" web/sites/default/settings.php 2>/dev/null; then
    if ! grep -q "nix-settings.php" web/sites/default/settings.php 2>/dev/null; then
      echo "❌ settings.php has hardcoded database config but no nix-settings include"
      echo "   This may cause conflicts. Consider regenerating settings.php"
      ((errors++))
    fi
  fi
  
  # 6. Check composer dependencies
  if [ ! -d "vendor" ]; then
    echo "❌ vendor directory missing - run: composer install"
    ((errors++))
  else
    echo "✓ vendor directory exists"
  fi
  
  if [ $errors -eq 0 ]; then
    echo ""
    echo "✅ All checks passed! Ready to install."
    return 0
  else
    echo ""
    echo "❌ $errors check(s) failed. Fix issues above before installing."
    return 1
  fi
}

# Usage
pre_install_checklist && drush site:install recipes/haven --yes
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
      b. **CRITICAL: Initialize git and .gitignore BEFORE starting services**
         ```bash
         # Handle .gitignore first
         if ! grep -q "^data/$" .gitignore 2>/dev/null; then
           echo -e "\n# Drupal-flake\ndata/" >> .gitignore
         fi
         
         # Then init git
         git init
         git add flake.nix flake.lock .env .envrc .gitignore .services/
         # Note: 'git add' is sufficient - Nix uses staged files, commit is optional
         ```
         ⚠️ Without git, MySQL socket will cause Nix to fail!
       c. **PROMPT USER - DO NOT SKIP, DO NOT USE DEFAULTS:**
          ⚠️ **ASK ALL 4 QUESTIONS, WAIT FOR RESPONSES:**
          ```
          1. "Project name? (detected: 'cms')" 
          2. "Port? (calculated: 2677, or choose 8080, 8888)"
          3. "PHP version? (default: php84, options: php74/php83)"
          4. "Starting point? (1=CMS/byte, 2=Commerce, 3=Vanilla)"
          ```
          - Calculate port with: suggest_port "$(basename $PWD)"
          - Wait for user to answer EACH question
          - Confirm back: "Using project='X', port=Y, php=Z, starting=W"
          - Only then create .env
      d. Create .env file with user CONFIRMED values
      e. Determine package and recipe:
         - Choice 1 → drupal/cms, DEMO_RECIPE="recipes/byte"
         - Choice 2 → centarro/commerce-kickstart-project
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

- **MUST ASK ALL 4 QUESTIONS** - Never skip prompts: project name, port, PHP version, starting point
- **Git is REQUIRED** - `git init` immediately after `nix flake init`, BEFORE starting services
- **Never auto-start DDev** - it may conflict with user's intent
- **Always check HTTP 200 first** - Site responding is the TRUE success metric
- **Process count is misleading** - "3/7 running" is SUCCESS after setup completes
- **Setup processes are supposed to exit** - cms, nix-settings, init complete and exit (this is NORMAL)
- **Use start-detached over nix run** - doesn't block the agent
- **Wait for HTTP response** - not "all processes running" (setup processes complete!)
- **Respect .env configuration** - especially PORT and DOMAIN
- **Calculate port correctly** - Phone keypad + name length: ABC=2, DEF=3, GHI=4, JKL=5, MNO=6, PQRS=7, TUV=8, WXYZ=9. cms→2675, core→2676, drupal→3788
- **Vanilla Core needs drush installed** - Unlike CMS or Kickstart, vanilla core doesn't include drush. The init script installs it automatically.
- **Use interactive prompts with arrow keys** - Don't just list defaults as text. Use pickers where user can press Enter or arrow through options.
- **Quote .env values with spaces** - `SITE_NAME="Commerce Kickstart"` not `SITE_NAME=Commerce Kickstart`. Don't add optional variables unless necessary.
- **Background vs Interactive** - `start-detached` is better for agents; `nix run` for user TUI
- **Use discrete commands for debugging** - If `start-demo` fails, use `drupal-download`, `drupal-recipe`, `drupal-install` individually
- **Get credentials via drush uli** - Don't wait for install output, generate fresh login link
- **MySQL socket causes Nix failures without git** - Socket files in data/ can't be tracked
