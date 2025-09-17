# Drupal Flake

A Nix-native way to get started with Drupal development. This is in early stages and not fully functional yet.

## Flake location
The main location for this flake is now on Drupal.org - please file issues at https://www.drupal.org/project/drupal_flake. It is also mirrored at Github, at https://github.com/freelock/drupal-flake .

Any of the following will work to run or download this flake:

- git+https://git.drupalcode.org/project/drupal_flake#demo
- gitlab:project/drupal_flake?host=git.drupalcode.org#demo
- github:freelock/drupal-flake#demo

## What works

Currently this flake:

- Uses Process Compose to launch:
  - A MariaDB server
  - Nginx
  - PHP-FPM
  - Drupal CMS install script
  - Script to add a setting.nix.php to connect to the MariaDB server
- Uses a .env file to specify project name, port, PHP version, docroot
- Provides a devShell that sets up drush to work with the installed site
- Provides xDebug configured to work with a trigger (e.g. a browser xdebug helper extension)
- Provides a template to make it easy to install and configure in an existing Drupal project


## Demo run target

You can install a minimal installation of Drupal CMS with a single command, without even cloning this repo!

```
nix run git+https://git.drupalcode.org/project/drupal_flake#demo
```
On my machine with warmed caches, this takes about 2 1/2 minutes to download Drupal CMS, provision a dev runtime environment, install Drupal, and open your browser to the new site.

In the shell you run this in, the "init" task will print the admin username and password.

## Config run target

If this flake is added to an existing project, you can install the site from config using `nix run .#config`. Or if you enter the dev-shell, there's a shortcut - `start-config`.

Note that this will clobber the existing database and do a fresh install from config. The config sync directory does need to be set correctly in $settings.

## Install locally

You can run this locally by installing the template:

```
nix flake init -t git+https://git.drupalcode.org/project/drupal_flake
nix run .#demo
```
This will install a fresh copy of Drupal CMS if you don't have one, and launch it all in one go!

The demo setup is skipped if the web/index.php file already exists -- it then just starts up the servers, so this is entirely non-destructive and safe to run.


## Setting name, port, domain

With the flake installed locally, you can now set the base project name, port, domain, PHP version, and Drupal package to install using env vars, with --impure. This works on the command line ahead of nix run.

```
PROJECT_NAME=myproject PORT=9901 DRUPAL_PACKAGE=drupal/recommended-project:^10.4 nix run --impure .#demo
```

You can set these variables in a .env file - but this is subject to how Nix Flakes handle files -
if you are in a git directory, the .env file needs to be added to git or else Nix will ignore it entirely.

Copy the .env.example to .env and edit as desired.

### Note on domain, port

To be able to resolve your site to localhost, you may need to add an entry to your /etc/hosts file. The DDev project has created a wildcard DNS that allows anything that ends in *.ddev.site to resolve to localhost. So by default the domain is set to the PROJECT_NAME.ddev.site, which should always work.

Ports must be higher than 1024, or else you need some sort of root access to be able to use them.

### PHP Versions

You can specify the PHP version to use by setting the `PHP_VERSION` environment variable or adding it to your `.env` file:

```
PHP_VERSION=php83  # Default, uses php83 from nixpkgs nixos-unstable
```

Available PHP versions include:
- php74 (from a pinned nixpkgs commit: 6e3a86f2f73a466656a401302d3ece26fba401d9)
  - Note: php74 does not include phpunit, php-codesniffer, and phpstan due to availability limitations
  - Includes the standalone drush command for older Drupal sites that use Drush 8
- php80, php81, php82, php83, php84 (from nixpkgs nixos-unstable)

### Local Extensions

You can extend the development environment with additional PHP extensions, Nix packages, and custom tools by creating a `nix/local-extensions.nix` file:

1. **Copy the template**: `cp local-extensions.nix.example nix/local-extensions.nix`
2. **Customize as needed**: The template includes examples for:
   - **Extra PHP extensions** (Redis, Memcached, etc.)
   - **Development tools** (Node.js, Python packages, etc.) 
   - **Custom tools and scripts**
   - **Additional PATH entries** for PHP-FPM access

**WeasyPrint Example**: The template includes a complete WeasyPrint setup for PDF generation:
- Python environment with WeasyPrint and dependencies
- Wrapper script for easy command-line usage
- Test script to verify installation
- PATH configuration so PHP can access the WeasyPrint binary

The `nix/` directory is excluded from `refresh-flake` updates, so your customizations persist across flake updates.

## Commands available in Dev Shell

### Development Commands:
**Basic Commands:**
- `nix run` - Start the development environment (interactive)
- `start` - Start the development environment (interactive)
- `start-detached` - Start the development environment in background
- `nix run .#demo` - Set up a new Drupal site, or start servers
- `start-demo` - Set up a new Drupal site, or start servers
- `start-config` - Start servers and install Drupal from config - **CLOBBERS EXISTING DATABASE**

**Process Management:**
- `pc-status` - Check if process-compose is running and show status
- `pc-attach` - Attach to running process-compose TUI (detach with F10)
- `pc-stop` - Stop the current project's development environment
- `stop-all` - Stop ALL process-compose development environments

**Development Tools:**
- `xdrush` - Run Drush with Xdebug enabled
- `nix-settings` - Add/include settings.nix.php (done automatically with start)
- `refresh-flake [path]` - Refresh the flake from Drupal.org or [path]
- `setup-starship-prompt` - Configure starship prompt to show process-compose status
- `?` - Show help message with all available commands

### Starship Prompt Integration

If you use [Starship](https://starship.rs/) for your shell prompt, run `setup-starship-prompt` to configure a status indicator that shows:
- `💧❄️ project-name` when process-compose is running for the current project
- Nothing when process-compose is not running

This gives you instant visual feedback about your development environment status across all shell sessions and subdirectories.

## Development Workflow

### Background Mode (Recommended)

For the best development experience, use the background mode:

1. **Start detached**: `start-detached` - Runs services in background
2. **Check status**: `pc-status` - Verify everything is running and get connection info
3. **Code away**: Your starship prompt shows when services are active
4. **Attach when needed**: `pc-attach` - Connect to the TUI to see logs or manage processes
5. **Stop cleanly**: `pc-stop` - Stop just this project's services

### Interactive Mode

For debugging or learning:

1. **Start interactive**: `start` or `nix run` - Shows TUI immediately
2. **Use F10 to detach** - Keeps services running in background
3. **Use `pc-attach`** to reconnect to the TUI

### Multiple Projects

You can run multiple projects simultaneously on different ports:
- Each project gets its own socket and status file
- `pc-stop` stops only the current project
- `stop-all` stops everything (nuclear option)
- Starship shows the current project's status

## Next up

This is currently working well, and has a nice developer experience. Here are some things we are considering for the future.

1. Add other supporting tools to the devShell -- scripts to import recipes/default content, import/pull databases, etc
2. SSL certs - possibly switch to Caddy
3. Helper to run on standard ports (80, 443)
4. Additional services -
  - Solr
  - PhpMyAdmin
  - Mailpit
  - Redis
5. Build - Create a Docker image, VM, or Nix Package
