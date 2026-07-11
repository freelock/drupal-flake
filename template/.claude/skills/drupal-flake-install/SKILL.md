---
name: drupal-flake-install
description: Install and configure Drupal sites. Handles start-demo workflow, recipe/site template discovery, profile selection (CMS, Kickstart, Core), and Drupal 12 installation.
compatibility: opencode
metadata:
  framework: Drupal
  primary_tool: drupal-flake
  secondary_tools: [composer, drush]
  features: [new-project-init, recipe-installation, profile-selection, drupal-12]
---

## Prerequisites (CRITICAL)

**Git initialization is REQUIRED before running setup-drupal:**
```bash
git init
cat > .gitignore << 'EOF'
data/
*.sock
web/sites/*/files/
web/sites/*/private/
vendor/
node_modules/
.env.local
EOF
```
⚠️ **Without git, MySQL socket files fail. setup-drupal will stage .env in git for you.**

## Installation Methods

### 1. setup-drupal (Recommended for new projects)
```bash
# Interactive setup (prompts for package, PHP, site name)
nix develop
setup-drupal
```

### 2. setup-settings (Add to existing projects)
```bash
# Generate a minimal settings.php without clobbering
setup-settings [--site <sitename>] [--project-name <name>]
```

### 3. start-demo (Quick demo/integration test)
```bash
nix develop
start-demo [package] [project-name] [--detached]
```

## Profile Selection Guide

| Profile | Package | Recipe | Use Case |
|---------|---------|--------|----------|
| **Drupal CMS** | `drupal/cms` | `recipes/byte` | Content management focus |
| **Commerce Kickstart** | `centarro/commerce-kickstart-project` | None | E-commerce |
| **Vanilla Core** | `drupal/recommended-project` | `standard` or `minimal` | Custom builds |

### Recipe Discovery
```bash
# Available in drupal/cms
cd web && find core/recipes -name "*.yml" | head -20

# Community recipes (after install)
drush recipe:validate recipes/contrib/<name>
```

### Drupal 12 Specifics
- Requires PHP 8.3+ (use `PHP_VERSION=php83`, `php84`, or `php85`)
- Some contrib modules may need `--stability=dev`
- Check core compatibility: `composer show drupal/core | grep versions`

## New Project Workflow

### Step 1: Enter devShell
```bash
# If using direnv:
direnv allow

# Otherwise:
nix develop
```

### Step 2: Run setup-drupal
```bash
setup-drupal [package] [php-version] [site-name]
```
Follow the interactive prompts. The script will:
- Generate a PORT from your site name (T9 keypad mapping)
- Write .env with your configuration
- Run composer create-project
- Generate a minimal settings.php
- Stage .env in git

### Step 3: Start the environment
```bash
# If using direnv:
start-detached

# Otherwise: first exit, then re-enter and start
exit
nix develop
start-detached
```

### Step 4: Monitor Installation
```bash
BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
until curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200"; do
  echo "Waiting..."
  sleep 15
done
drush uli
```

## Site Template Recipes

### CMS Recipes
```bash
# List available
ls web/core/recipes/ 2>/dev/null | head -10

# Apply recipe (after base install)
drush recipe recipes/<name>
```

### Community Site Templates
```bash
# Find on marketplace or packagist
composer require drupal/<recipe-name>
drush recipe recipes/<recipe-name>
```

## Troubleshooting Installation

**Download fails:**
```bash
# Check logs
cat data/install.log 2>/dev/null | tail -50

# Retry with verbose
start-demo --verbose
```

**Recipe not found:**
- Recipe format: `vendor/name` (e.g., `drupal/haven`)
- Must be a composer package with recipe metadata

**Missing modules:**
```bash
# Auto-install detected missing modules
grep -oE "Module ['\"]?[a-z_]+['\"]? not found" data/install.log 2>/dev/null | \
  sed -E "s/.*['\"]?([a-z_]+)['\"]?.*/\1/" | sort -u | \
  xargs -I {} composer require drupal/{}
```

**Database locked:**
```bash
stop-all
rm -rf data/db/*
start-detached
```

## Advanced: start-config

⚠️ **WARNING:** `start-config` **DESTROYS** existing database!
```bash
# Only for fresh re-installs
start-config
```
