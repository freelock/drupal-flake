#!/usr/bin/env bash
#
# common.sh — Shared functions for drupal-flake scripts
#
# Embedded at build time via readFile concatenation — not sourced directly.
#

set -e

# generate_port: Derive a deterministic HTTP port from a project name
# Uses T9 phone keypad mapping on first 8 chars of name, adds 2
# Capped at 65535 to stay within valid port range.
generate_port() {
  local name="$1"
  local digits=""
  local i char
  for (( i=0; i<${#name} && i<8; i++ )); do
    char="${name:$i:1}"
    case "$char" in
      [aAbBcC]) digits+="2" ;;
      [dDeEfF]) digits+="3" ;;
      [gGhHiI]) digits+="4" ;;
      [jJkKlL]) digits+="5" ;;
      [mMnNoO]) digits+="6" ;;
      [pPqQrRsS]) digits+="7" ;;
      [tTuUvV]) digits+="8" ;;
      [wWxXyYzZ]) digits+="9" ;;
      0) digits+="0" ;;
      1) digits+="1" ;;
      2|3|4|5|6|7|8|9) digits+="$char" ;;
    esac
  done
  if [ -z "$digits" ]; then
    echo 8080
    return
  fi
  local port=$(( 10#$digits + 2 ))
  if [ "$port" -gt 65535 ]; then
    port=8080
  fi
  echo "$port"
}

# write_env_from_example: Create .env from .env.example with filled values
# Arguments: PROJECT_NAME PHP_VERSION PORT
write_env_from_example() {
  local project_name="$1"
  local php_version="$2"
  local port="$3"

  if [ ! -f ".env.example" ]; then
    echo "Error: .env.example not found in current directory"
    return 1
  fi

  if [ -f ".env" ]; then
    echo "Warning: .env already exists, overwriting"
  fi

  cp .env.example .env

  # Detect sed in-place flag (GNU vs BSD)
  local sed_i
  if sed --version 2>/dev/null | grep -q GNU; then
    sed_i=(-i)
  else
    sed_i=(-i '')
  fi

  sed "${sed_i[@]}" "s/^# PROJECT_NAME=.*/PROJECT_NAME=$project_name/" .env
  sed "${sed_i[@]}" "s/^# DOMAIN=.*/DOMAIN=$project_name.ddev.site/" .env
  sed "${sed_i[@]}" "s/^# PORT=.*/PORT=$port/" .env
  sed "${sed_i[@]}" "s/^# PHP_VERSION=.*/PHP_VERSION=$php_version/" .env
  sed "${sed_i[@]}" "s/^# DOCROOT=.*/DOCROOT=web/" .env
  sed "${sed_i[@]}" "s/^# SITE_NAME=.*/SITE_NAME=$project_name/" .env

  echo "Wrote .env with PROJECT_NAME=$project_name, PHP_VERSION=$php_version, PORT=$port"
}

# flatten_subdirectory: Move contents of a subdirectory up, then remove it
# Used after composer create-project places files in a subdirectory
flatten_subdirectory() {
  local subdir="$1"

  if [ ! -d "$subdir" ]; then
    return 0
  fi

  echo "Moving files from $subdir to current directory..."

  for item in "$subdir"/* "$subdir"/.[!.]* "$subdir"/..?*; do
    [ -e "$item" ] || continue
    local base
    base=$(basename "$item")
    if [ -e "$base" ]; then
      if [ -d "$item" ] && [ -d "$base" ]; then
        cp -r "$item"/* "$base"/ 2>/dev/null || true
        cp -r "$item"/.[!.]* "$base"/ 2>/dev/null || true
      else
        rm -rf "$base"
        mv "$item" ./ || true
      fi
    else
      mv "$item" ./ || true
    fi
  done

  if rmdir "$subdir" 2>/dev/null; then
    echo "Removed empty $subdir directory"
  else
    echo "Warning: $subdir not empty, manual cleanup may be needed"
  fi
}
