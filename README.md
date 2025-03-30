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


## Next up

The Demo target installs a clean new copy of Drupal CMS -- but what about existing projects?

`nix run` without a target (the default) starts up all the servers, and assumes a document root of /web. Coming soon:

1. Add other supporting tools to the devShell -- scripts to hook things up, mysql/mariadb, etc
2. SSL certs - possibly switch to Caddy
3. Helper to run on standard ports (80, 443)
4. Additional services -
  - Solr
  - PhpMyAdmin
  - Mailpit
  - Redis
5. Build - Create a Docker image, VM, or Nix Package
