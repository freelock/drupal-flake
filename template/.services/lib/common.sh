#!/usr/bin/env bash
#
# common.sh — Shared functions for drupal-flake scripts
#
# Embedded at build time via readFile concatenation — not sourced directly.
#

set -e

# generate_port: Derive a deterministic HTTP port from a project name
# Uses T9 phone keypad mapping on first 3 chars, appends the last char's
# T9 digit (when name > 3 chars), then adds 2000 to stay above common ports.
# This keeps results well under 65535 and gives distinct ports for names
# that share a prefix but differ in the last character (test1 vs test2).
generate_port() {
  local name="$1"
  local digits=""
  local i char
  for (( i=0; i<${#name} && i<3; i++ )); do
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
  if [ ${#name} -gt 3 ]; then
    char="${name: -1}"
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
  fi
  if [ -z "$digits" ]; then
    echo 8080
    return
  fi
  echo $(( 10#$digits + 2000 ))
}

# env_file_value: Print the first active value for a key in .env.
env_file_value() {
  local key="$1"
  [ -f .env ] || return 1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' .env
}

# set_env_value: Replace a key (including a commented example) or append it.
set_env_value() {
  local key="$1"
  local value="$2"
  local tmp
  tmp=$(mktemp)
  awk -v key="$key" -v value="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^[[:space:]#]*" key "=" && !replaced {
      print key "=" value
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) print key "=" value }
  ' .env > "$tmp"
  mv "$tmp" .env
}

# append_env_value_if_missing: Preserve .env and add only absent active keys.
append_env_value_if_missing() {
  local key="$1"
  local value="$2"
  if ! awk -F= -v key="$key" '$1 == key { found = 1 } END { exit !found }' .env; then
    if [ -s .env ] && [ -n "$(tail -c 1 .env)" ]; then
      printf '\n' >> .env
    fi
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

# write_env_from_example: Fill the flake-owned .env keys safely.
# Arguments: PROJECT_NAME PHP_VERSION PORT DOCROOT FORCE_ENV
write_env_from_example() {
  local project_name="$1"
  local php_version="$2"
  local port="$3"
  local docroot="${4:-web}"
  local force_env="${5:-false}"

  if [ "$force_env" = true ]; then
    if [ ! -f .env.example ]; then
      echo "Error: .env.example not found in current directory"
      return 1
    fi
    cp .env.example .env
    set_env_value PROJECT_NAME "$project_name"
    set_env_value DOMAIN "$project_name.ddev.site"
    set_env_value PORT "$port"
    set_env_value PHP_VERSION "$php_version"
    set_env_value DOCROOT "$docroot"
    set_env_value SITE_NAME "$project_name"
    echo "Replaced .env from .env.example"
  else
    [ -f .env ] || : > .env
    append_env_value_if_missing PROJECT_NAME "$project_name"
    append_env_value_if_missing DOMAIN "$project_name.ddev.site"
    append_env_value_if_missing PORT "$port"
    append_env_value_if_missing PHP_VERSION "$php_version"
    append_env_value_if_missing DOCROOT "$docroot"
    append_env_value_if_missing SITE_NAME "$project_name"
    echo "Preserved .env and filled missing drupal-flake settings"
  fi
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
