#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"

cat "$ROOT/template/.services/lib/common.sh" \
  "$ROOT/template/.services/bin/setup-drupal" > "$BIN/setup-drupal"
chmod +x "$BIN/setup-drupal"

cat > "$BIN/composer" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$TEST_COMPOSER_LOG"
case "$1" in
  create-project)
    mkdir -p "$3/web/core/lib"
    printf '<?php // generated Drupal\n' > "$3/web/index.php"
    printf '<?php // generated Drupal core\n' > "$3/web/core/lib/Drupal.php"
    printf '{"name":"fixture/generated"}\n' > "$3/composer.json"
    ;;
  install) ;;
  *) echo "Unexpected Composer command: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$BIN/composer"

cat > "$BIN/setup-settings" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$TEST_SETUP_LOG"
exec "$ROOT/template/.services/bin/setup-settings" "\$@"
EOF
chmod +x "$BIN/setup-settings"

cat > "$BIN/nix-settings" <<'EOF'
#!/usr/bin/env bash
set -eu
project_name="$1"
docroot="$2"
prefix="${docroot%/}"
[ "$prefix" = "." ] && prefix=""
settings="${prefix:+$prefix/}sites/default/settings.php"
[ -f "$settings" ] || { echo "nix-settings called before $settings existed" >&2; exit 1; }
printf '%s|%s|%s\n' "$project_name" "$docroot" "${4:-}" >> "$TEST_NIX_LOG"
printf '<?php // nix fixture\n' > "${settings%/*}/settings.nix.php"
EOF
chmod +x "$BIN/nix-settings"

export PATH="$BIN:$PATH"
export TEST_COMPOSER_LOG="$TMP/composer.log"
export TEST_SETUP_LOG="$TMP/setup-settings.log"
export TEST_NIX_LOG="$TMP/nix-settings.log"

write_env_example() {
  cat > .env.example <<'EOF'
# Drupal flake fixture
# PROJECT_NAME=drupal-demo
# DOMAIN=drupal-demo.ddev.site
# PORT=8088
# PHP_VERSION=php84
# DOCROOT=web
# SITE_NAME=drupal-demo
EXAMPLE_ONLY=kept-on-force
EOF
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fqx -- "$expected" "$file" || {
    echo "Expected '$expected' in $file" >&2
    cat "$file" >&2
    exit 1
  }
}

reset_logs() {
  : > "$TEST_COMPOSER_LOG"
  : > "$TEST_SETUP_LOG"
  : > "$TEST_NIX_LOG"
}

echo "Test: help documents modern modes and mutually exclusive modes are rejected"
setup-drupal --help | grep -Fq -- '--existing'
setup-drupal --help | grep -Fq -- '--force-env'
if setup-drupal --existing --new --non-interactive >"$TMP/mutually-exclusive.log" 2>&1; then
  echo "Mutually exclusive modes were unexpectedly accepted" >&2
  exit 1
fi
grep -Fq 'mutually exclusive' "$TMP/mutually-exclusive.log"

echo "Test: existing web project preserves code, settings, and .env without Composer"
fixture="$TMP/existing-web"
mkdir -p "$fixture/web/core/lib" "$fixture/web/sites/default"
printf '<?php // index sentinel\n' > "$fixture/web/index.php"
printf '<?php // core sentinel\n' > "$fixture/web/core/lib/Drupal.php"
printf '<?php // settings sentinel\n' > "$fixture/web/sites/default/settings.php"
cat > "$fixture/.env" <<'EOF'
PROJECT_NAME=preserved-name
DOMAIN=preserved.example.test
PORT=9123
PHP_VERSION=php83
DOCROOT=web
CUSTOM_SECRET=do-not-touch
EOF
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --existing --non-interactive --site-name ignored --php-version php85 --port 9999
  assert_contains web/index.php '<?php // index sentinel'
  assert_contains web/core/lib/Drupal.php '<?php // core sentinel'
  assert_contains web/sites/default/settings.php '<?php // settings sentinel'
  assert_contains .env 'PROJECT_NAME=preserved-name'
  assert_contains .env 'DOMAIN=preserved.example.test'
  assert_contains .env 'PORT=9123'
  assert_contains .env 'PHP_VERSION=php83'
  assert_contains .env 'CUSTOM_SECRET=do-not-touch'
  assert_contains .env 'SITE_NAME=preserved-name'
  [ ! -s "$TEST_COMPOSER_LOG" ] || { echo "Composer was invoked in existing mode" >&2; exit 1; }
  [ ! -s "$TEST_SETUP_LOG" ] || { echo "setup-settings ran despite existing settings.php" >&2; exit 1; }
  assert_contains "$TEST_NIX_LOG" 'preserved-name|web|..'
)

echo "Test: auto-detected root docroot creates settings before nix-settings"
fixture="$TMP/existing-root"
mkdir -p "$fixture/core/lib"
printf '<?php // root index sentinel\n' > "$fixture/index.php"
printf '<?php // root core sentinel\n' > "$fixture/core/lib/Drupal.php"
printf 'CUSTOM_VALUE=survives' > "$fixture/.env"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --non-interactive --site-name root-site
  assert_contains index.php '<?php // root index sentinel'
  assert_contains .env 'CUSTOM_VALUE=survives'
  assert_contains .env 'DOCROOT=.'
  [ -f sites/default/settings.php ]
  assert_contains "$TEST_SETUP_LOG" '--project-name root-site --docroot .'
  assert_contains "$TEST_NIX_LOG" 'root-site|.|.'
  [ ! -s "$TEST_COMPOSER_LOG" ] || { echo "Composer was invoked for auto-detected Drupal" >&2; exit 1; }
)

echo "Test: Composer metadata is treated as an existing Drupal project before install"
fixture="$TMP/existing-composer-only"
mkdir -p "$fixture"
cat > "$fixture/composer.json" <<'EOF'
{"require":{"drupal/core-recommended":"^11"}}
EOF
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --non-interactive --site-name composer-site
  [ -f composer.json ]
  grep -Fq 'drupal/core-recommended' composer.json
  [ -f web/sites/default/settings.php ]
  [ ! -s "$TEST_COMPOSER_LOG" ] || { echo "Composer was invoked over an existing Drupal Composer project" >&2; exit 1; }
)

echo "Test: explicit --existing refuses a directory without Drupal code"
fixture="$TMP/refuse-existing"
mkdir -p "$fixture"
(
  cd "$fixture"
  reset_logs
  if setup-drupal --existing --non-interactive >output.log 2>&1; then
    echo "--existing unexpectedly accepted a directory without Drupal" >&2
    exit 1
  fi
  grep -Fq "no Drupal code was found" output.log
  [ ! -s "$TEST_COMPOSER_LOG" ]
)

echo "Test: --force-env is the explicit path that replaces .env"
fixture="$TMP/force-env"
mkdir -p "$fixture/web/core" "$fixture/web/sites/default"
printf '<?php // force fixture\n' > "$fixture/web/index.php"
printf '<?php // settings fixture\n' > "$fixture/web/sites/default/settings.php"
cat > "$fixture/.env" <<'EOF'
PROJECT_NAME=old-name
CUSTOM_SECRET=removed-by-force
DOCROOT=web
EOF
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --existing --non-interactive --force-env \
    --site-name forced-name --php-version php85 --port 9555
  assert_contains .env 'PROJECT_NAME=forced-name'
  assert_contains .env 'PHP_VERSION=php85'
  assert_contains .env 'PORT=9555'
  assert_contains .env 'EXAMPLE_ONLY=kept-on-force'
  ! grep -Fq 'CUSTOM_SECRET=removed-by-force' .env
  [ ! -s "$TEST_COMPOSER_LOG" ]
)

echo "Test: explicit --new refuses an existing Drupal project"
fixture="$TMP/refuse-new"
mkdir -p "$fixture/web/core"
printf '<?php\n' > "$fixture/web/index.php"
(
  cd "$fixture"
  reset_logs
  if setup-drupal --new --non-interactive >output.log 2>&1; then
    echo "--new unexpectedly accepted existing Drupal code" >&2
    exit 1
  fi
  grep -Fq "Drupal code already exists" output.log
  [ ! -s "$TEST_COMPOSER_LOG" ]
)

echo "Test: new mode works offline and preserves a pre-existing .env"
fixture="$TMP/new-modern"
mkdir -p "$fixture"
cat > "$fixture/.env" <<'EOF'
PROJECT_NAME=env-name-survives
CUSTOM_SECRET=new-mode-secret
EOF
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive \
    --package drupal/recommended-project \
    --php-version php85 \
    --site-name modern-site \
    --port 9456
  [ -f web/index.php ]
  [ -f composer.json ]
  [ -f web/sites/default/settings.php ]
  assert_contains .env 'PROJECT_NAME=env-name-survives'
  assert_contains .env 'CUSTOM_SECRET=new-mode-secret'
  assert_contains .env 'PHP_VERSION=php85'
  assert_contains .env 'PORT=9456'
  assert_contains .env 'DOCROOT=web'
  grep -Fq 'create-project drupal/recommended-project' "$TEST_COMPOSER_LOG"
  assert_contains "$TEST_COMPOSER_LOG" 'install'
  assert_contains "$TEST_SETUP_LOG" '--project-name env-name-survives --docroot web'
  assert_contains "$TEST_NIX_LOG" 'env-name-survives|web|..'
)

echo "Test: legacy positional package/PHP/site arguments still work"
fixture="$TMP/new-legacy"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive drupal/cms php83 legacy-site
  grep -Fq 'create-project drupal/cms' "$TEST_COMPOSER_LOG"
  assert_contains .env 'PROJECT_NAME=legacy-site'
  assert_contains .env 'PHP_VERSION=php83'
)

echo "Test: setup-settings honors a nested --docroot"
fixture="$TMP/nested-docroot"
mkdir -p "$fixture"
(
  cd "$fixture"
  "$ROOT/template/.services/bin/setup-settings" --project-name nested-site --docroot ./public/drupal/
  [ -f public/drupal/sites/default/settings.php ]
  grep -Fq "config_sync_directory'] = '../../config/sync'" public/drupal/sites/default/settings.php
  grep -Fq '../../data/nested-site-db/mysql.sock' public/drupal/sites/default/settings.php
)

echo "Test: --help documents --core"
setup-drupal --help | grep -Fq -- '--core VERSION'

echo "Test: --core 12 targets the pre-release line with dev stability and PHP 8.5"
fixture="$TMP/core-12"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive --core 12 --site-name d12-site --port 9460
  grep -Fq 'create-project drupal/recommended-project:^12@dev' "$TEST_COMPOSER_LOG"
  grep -Fq -- '--stability=dev' "$TEST_COMPOSER_LOG"
  grep -Fq -- '--prefer-stable' "$TEST_COMPOSER_LOG"
  # composer install must not re-resolve onto pre-release branches, but it
  # still gets --prefer-stable so it can keep the locked stable versions.
  assert_contains "$TEST_COMPOSER_LOG" 'install --prefer-stable'
  # Drupal 12 needs PHP 8.5, which the default php84 does not satisfy.
  assert_contains .env 'PHP_VERSION=php85'
)

echo "Test: the interactive package menu offers the pre-release core and raises PHP for it"
fixture="$TMP/core-12-interactive"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  # site name, then defaults for PHP, then package choice 4, then default port.
  printf 'interactive-core-site\n\n4\n\n' | setup-drupal >run.log 2>&1
  grep -Fq 'drupal/recommended-project:^12 (Drupal core NEXT' run.log
  grep -Fq 'create-project drupal/recommended-project:^12@dev' "$TEST_COMPOSER_LOG"
  grep -Fq -- '--stability=dev' "$TEST_COMPOSER_LOG"
  # Accepting the default PHP at the prompt is not an explicit choice, so the
  # core gets to raise it to the version Drupal 12 needs.
  grep -Fq 'Raising PHP to php85' run.log
  assert_contains .env 'PHP_VERSION=php85'
)

echo "Test: --core 11 stays on stable without dev stability"
fixture="$TMP/core-11"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive --core 11 --site-name d11-site --port 9461
  grep -Fq 'create-project drupal/recommended-project:^11 ' "$TEST_COMPOSER_LOG"
  ! grep -Fq -- '--stability' "$TEST_COMPOSER_LOG"
  assert_contains "$TEST_COMPOSER_LOG" 'install'
  # Core 11 only needs PHP 8.3, so the default php84 is already good enough.
  assert_contains .env 'PHP_VERSION=php84'
)

echo "Test: a non-core-versioned package cannot target a core without a stable release"
fixture="$TMP/core-12-cms"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  if setup-drupal --new --non-interactive --core 12 \
    --package drupal/cms --site-name cms-site >output.log 2>&1; then
    echo "--core 12 was unexpectedly accepted for drupal/cms" >&2
    exit 1
  fi
  grep -Fq 'versioned independently of Drupal core' output.log
  [ ! -s "$TEST_COMPOSER_LOG" ]
)

echo "Test: --core 11 accepts an independently versioned package with a note"
fixture="$TMP/core-11-cms"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive --core 11 \
    --package drupal/cms --site-name cms11-site --port 9462 2>note.log
  grep -Fq 'does not constrain' note.log
  grep -Fq 'create-project drupal/cms ' "$TEST_COMPOSER_LOG"
  ! grep -Fq -- '--stability' "$TEST_COMPOSER_LOG"
)

echo "Test: --core refuses to run against an existing project"
fixture="$TMP/core-existing"
mkdir -p "$fixture/web/core/lib"
printf '<?php // index\n' > "$fixture/web/index.php"
printf '<?php // core\n' > "$fixture/web/core/lib/Drupal.php"
(
  cd "$fixture"
  write_env_example
  reset_logs
  if setup-drupal --existing --non-interactive --core 12 >output.log 2>&1; then
    echo "--core was unexpectedly accepted with --existing" >&2
    exit 1
  fi
  grep -Fq -- '--core only applies when creating a new project' output.log
  [ ! -s "$TEST_COMPOSER_LOG" ]
)

echo "Test: an explicitly requested PHP below the core minimum is refused"
fixture="$TMP/core-12-old-php"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  if setup-drupal --new --non-interactive --core 12 \
    --php-version php84 --site-name old-php-site >output.log 2>&1; then
    echo "php84 was unexpectedly accepted for Drupal 12" >&2
    exit 1
  fi
  grep -Fq 'requires PHP php85 or newer' output.log
  [ ! -s "$TEST_COMPOSER_LOG" ]
)

echo "Test: a pre-release constraint in .env enables dev stability on its own"
fixture="$TMP/env-pre-release"
mkdir -p "$fixture"
cat > "$fixture/.env" <<'EOF'
DRUPAL_PACKAGE=drupal/recommended-project:^12
PHP_VERSION=php85
EOF
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive --site-name env-core-site --port 9463
  grep -Fq 'create-project drupal/recommended-project:^12@dev' "$TEST_COMPOSER_LOG"
  grep -Fq -- '--stability=dev' "$TEST_COMPOSER_LOG"
  assert_contains .env 'PHP_VERSION=php85'
)

echo "Test: an already pinned pre-release package keeps its own stability flag"
fixture="$TMP/explicit-stability"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive \
    --package 'drupal/recommended-project:12.0.0-alpha1@alpha' \
    --php-version php85 --site-name pinned-site --port 9464
  grep -Fq 'create-project drupal/recommended-project:12.0.0-alpha1@alpha ' "$TEST_COMPOSER_LOG"
  ! grep -Fq 'alpha1@alpha@dev' "$TEST_COMPOSER_LOG"
  grep -Fq -- '--stability=dev' "$TEST_COMPOSER_LOG"
)

echo "Test: an exact pin on a stable core adds no stability flags"
fixture="$TMP/exact-stable"
mkdir -p "$fixture"
(
  cd "$fixture"
  write_env_example
  reset_logs
  setup-drupal --new --non-interactive \
    --package 'drupal/recommended-project:11.2.5' \
    --site-name pinned-stable-site --port 9465
  grep -Fq 'create-project drupal/recommended-project:11.2.5 ' "$TEST_COMPOSER_LOG"
  ! grep -Fq -- '--stability' "$TEST_COMPOSER_LOG"
)

echo "All setup-drupal fixture tests passed"
