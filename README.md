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

## Run demo locally

You can run this locally by cloning this repo, and then simply `nix run .#demo`.

The demo setup is skipped if the web/index.php file already exists.

## Setting name, port, domain

You can now set the base project name, port, domain, PHP version, and Drupal package to install using env vars, with --impure. This works on the command line ahead of nix run.

```
PROJECT_NAME=myproject PORT=9901 DRUPAL_PACKAGE=drupal/recommended-project:^10.4 nix run --impure .#demo
```
.env support for these variables is planned, but not yet working.


## Coming soon

2. Make a template

This will allow you to use `nix init --flake github:freelock/drupal-flake#cms` to create a new project with Drupal CMS ready to install, or `nix init --flake github:freelock/drupal-flake` to install the dev stack in an existing Drupal project.
