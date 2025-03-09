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

## Coming soon

Actively working on this. The next target: 1. Get Drupal CMS running.

```
nix run .#demo
nix run github:freelock/drupal-flake#demo
```
This target will download and set up Drupal CMS, ready for installation.

2. Make a template

This will allow you to use `nix init --flake github:freelock/drupal-flake#cms` to create a new project with Drupal CMS ready to install, or `nix init --flake github:freelock/drupal-flake` to install the dev stack in an existing Drupal project.
