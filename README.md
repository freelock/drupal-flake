# Drupal Flake

A Nix-native way to get started with Drupal development. This is in early stages and not fully functional yet.

## What works

Currently this provides a run target and a dev shell.

You can run from this repo without downloading:

```
nix run github:freelock/drupal-flake
```
(currently failing until you create a "web" directory).

You can clone this repo to get a dev shell:

```
git clone https://github.com/freelock/drupal-flake.git
cd drupal-flake
```
... at this point if you have direnv active, you can use `direnv allow` to start a devShell with PHP8.3 available.

Or use `nix develop`.

With a local copy, you can update the programName and port near the top of the flake.nix, and then `nix run` to run your local copy.

## Demo run target

You can install a minimal installation of Drupal CMS with a single command, without even cloning this repo!

```
nix run github:freelock/drupal-flake#demo
```
On my machine with warmed caches, this takes about 2 1/2 minutes to download Drupal CMS, provision a dev runtime environment, install Drupal, and open your browser to the new site.

In the shell you run this in, the "init" task will print the admin username and password.

## Install locally

You can run this locally by installing the template:

```
nix flake init -t github:freelock/drupal-flake
nix run .#demo
```
This will install a fresh copy of Drupal CMS if you don't have one, and launch it all in one go!

The demo setup is skipped if the web/index.php file already exists.

If you already have a flake.nix and you want to use ours instead, you can add --refresh to the init command to overwrite the files in your local directory from templates/ in this repo:

```
nix flake init -t github:freelock/drupal-flake --refresh
```

## Setting name, port, domain

You can now set the base project name, port, domain, PHP version, and Drupal package to install using env vars, with --impure. This works on the command line ahead of nix run.

```
PROJECT_NAME=myproject PORT=9901 DRUPAL_PACKAGE=drupal/recommended-project:^10.4 nix run --impure .#demo
```

You can set these variables in a .env file - but this is subject to how Nix Flakes handle files -
if you are in a git directory, the .env file needs to be added to git or else Nix will ignore it entirely.

Copy the .env.example to .env and edit as desired.

### Note on domain, port

To be able to resolve your site to localhost, you may need to add an entry to your /etc/hosts file. The DDev project has created a wildcard DNS that allows anything that ends in .ddev.site to resolve to localhost. So by default the domain is set to the PROJECT_NAME.ddev.site, which should always work.

Ports must be higher than 1024, or else you need some sort of root access to be able to use them.


## Next up

The Demo target installs a clean new copy of Drupal CMS -- but what about existing projects?

`nix run` starts up all the servers, and assumes a document root of /web. Coming soon:

1. Make webroot configurable
2. Fix existing settings.php to load settings.nix.php
3. Make `drush sqlc` work -- currently erroring out due to no TTY
4. Add other supporting tools to the devShell -- scripts to hook things up, mysql/mariadb, etc
5. Fix Nginx's extra listen on port 8080 that prevents multiple instances from running
6. SSL certs - possibly switch to Caddy
7. Helper to run on standard ports (80, 443)
8. Additional services -
  - Solr
  - PhpMyAdmin
  - Mailpit
  - Redis
9. Build - Create a Docker image, VM, or Nix Package
