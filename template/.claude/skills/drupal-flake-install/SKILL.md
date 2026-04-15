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

**Git initialization is REQUIRED:**
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
git add flake.nix flake.lock .env .envrc .gitignore .services/
```
⚠️ **Without git, MySQL socket files fail.**

## Installation Methods

### 1. start-demo (Recommended)
```bash
# Interactive setup
nix develop
start-demo [package] [project-name] [--detached]
```

**Environment variables for customization:**
```bash
export DEMO_DRUPAL_PACKAGE="drupal/cms"  # or "drupalcommerce/commerce_kickstart"
export DEMO_COMPOSER_OPTIONS="--stability=dev"
export DEMO_RECIPE="recipes/byte"  # for CMS
```

### 2. Manual Composer
```bash
composer create-project drupal/recommended-project mysite
cd mysite && nix flake init -t /path/to/drupal-flake
```

## Profile Selection Guide

| Profile | Package | Recipe | Use Case |
|---------|---------|--------|----------|
| **Drupal CMS** | `drupal/cms` | `recipes/byte` | Content management focus |
| **Commerce Kickstart** | `drupalcommerce/commerce_kickstart` | None | E-commerce |
| **Vanilla Core** | `drupal/recommended-project` | `standard` or `minimal` | Custom builds |

### Recipe Discovery
```bash
# Available in drupal/cms
cd web && find core/recipes -name "*.yml" | head -20

# Community recipes (after install)
drush recipe:validate recipes/contrib/<name>
```

### Drupal 12 Specifics
- Requires PHP 8.3+ (use `PHP_VERSION=php83` or `php84`)
- Some contrib modules may need `--stability=dev`
- Check core compatibility: `composer show drupal/core | grep versions`

## New Project Workflow

### Step 1: Collect 4 Required Answers
```
1. Project name? (alphanumeric, no spaces)
2. HTTP port? (e.g., 2675 for "cms", 8080 default)
3. PHP version? (php84 recommended, php83 for D12)
4. Starting point? (1: CMS, 2: Kickstart, 3: Core)
```

### Step 2: Create Configuration
```bash
cat > .env << EOF
PROJECT_NAME=<name>
DOMAIN=<name>.ddev.site
PORT=<port>
PHP_VERSION=<php84|php83>
DOCROOT=web
EOF
```

### Step 3: Initialize
```bash
# Git setup first!
git init
git add .env .gitignore flake.nix .services/

# Enter shell and install
nix develop
start-demo --detached
```

### Step 4: Monitor Installation
```bash
# Wait for HTTP 200 (NOT process count!)
BASE_URL="http://$(grep DOMAIN .env | cut -d= -f2):$(grep PORT .env | cut -d= -f2)"
until curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200"; do
  echo "Waiting...$(pc-status | grep -c running)"
  sleep 15
done

# Get login link
drush uli
```

**Note:** Init processes exit after completion. "3/7 running" after setup is SUCCESS.

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
