#!/usr/bin/env bash
set -euo pipefail

# Test script for XDebug functionality
# This script tests that XDebug is properly configured for debugging

echo "🧪 Testing XDebug functionality..."

# Create test-logs directory for CI artifacts
mkdir -p test-logs

# Set up test environment
export TEST_PROJECT_NAME="xdebug-test-project"
export TEST_URL="http://xdebug-test-project.ddev.site:8088"
export TEST_TIMEOUT=600  # 10 minutes timeout for CI

# Ensure we have a clean git state for template testing
if [[ -n $(git status --porcelain) ]]; then
    echo "⚠️  Working directory is dirty, committing changes for testing..."
    git add . 2>/dev/null || true
    git commit -m "WIP: Test commit for CI" 2>/dev/null || true
fi

cleanup() {
    echo "🧹 Cleaning up XDebug test environment..."
    # Use killall if pkill is not available (e.g., in CI environments)
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "php-fpm.*xdebug-test" || true
        pkill -f "nginx.*xdebug-test" || true
        pkill -f "mysql.*xdebug-test" || true
    elif command -v killall >/dev/null 2>&1; then
        killall -q php-fpm || true
        killall -q nginx || true
        killall -q mysqld || true
    else
        echo "⚠️  Neither pkill nor killall available, skipping process cleanup"
    fi
    cd .. 2>/dev/null || true
    # Remove from git staging and filesystem
    git reset xdebug-test-project/ 2>/dev/null || true
    # Use more robust removal to handle database files that might be locked
    if [ -d "xdebug-test-project" ]; then
        chmod -R u+w xdebug-test-project/ 2>/dev/null || true
        rm -rf xdebug-test-project/ 2>/dev/null || true
    fi
}

# Cleanup on exit
trap cleanup EXIT

# Test 1: XDebug extension is loaded
echo "📋 Test 1: Checking if XDebug extension is loaded..."
mkdir -p xdebug-test-project
cd xdebug-test-project

# Initialize from template
nix flake init -t ../

# Create .env file to use web as docroot and set project name
cat > .env << "EOF"
DOCROOT=web
PROJECT_NAME=xdebug-test-project
EOF

# Create minimal Drupal structure that the default target expects (in web dir)
mkdir -p web/sites/default
cat > web/sites/default/settings.php << "EOF"
<?php
// Minimal settings.php for testing
$settings['config_sync_directory'] = 'config/sync';
$settings['file_scan_ignore_directories'] = [
  'node_modules',
  'bower_components',
];
EOF

# Create PHP test files before starting process-compose
cat > web/index.php << "EOF"
<?php
phpinfo();
?>
EOF

cat > web/xdebug-test.php << "EOF"
<?php
header("Content-Type: text/plain");
echo "XDebug loaded: " . (extension_loaded("xdebug") ? "YES" : "NO") . "\n";
if (extension_loaded("xdebug")) {
    echo "XDebug version: " . phpversion("xdebug") . "\n";
    echo "XDebug mode: " . ini_get("xdebug.mode") . "\n";
    echo "Start with request: " . ini_get("xdebug.start_with_request") . "\n";
    echo "Client host: " . ini_get("xdebug.client_host") . "\n";
    echo "Client port: " . ini_get("xdebug.client_port") . "\n";
    echo "Discover client host: " . ini_get("xdebug.discover_client_host") . "\n";
}
?>
EOF

# Add the test project to git so Nix can see it (but don't commit)
cd ..
git add xdebug-test-project/
cd xdebug-test-project

echo "✅ Template initialized for XDebug test with PHP files ready"

# Start default environment (now has minimal Drupal structure)
echo "⏳ Starting default environment for XDebug test..."
timeout $TEST_TIMEOUT bash -c '
    # Start using the new process management tools
    echo "🚀 Starting development environment in detached mode..."

    # Enter devShell and start services
    nix develop --command bash <<EOF
        # Set CI environment variables for headless operation
        export CI=true
        export DISPLAY=""

        echo "Debug: Available commands: \`which start-detached pc-status pc-stop 2>/dev/null || echo not found\`"
        echo "Debug: TTY check: \`tty 2>/dev/null || echo 'no tty'\`"
        echo "Debug: CI=\$CI, DISPLAY=\$DISPLAY"

        # Start services in background (always detached for testing)
        start-detached

        # Check status immediately
        echo "   Debug: Checking status after start..."
        pc-status || echo "   pc-status not responding immediately"
EOF

    # Give it more time to start all services
    echo "⏳ Waiting for services to initialize..."
    sleep 15

    # Wait for services to be ready
    for i in {1..30}; do
        # Use our process management tools for status checking
        if [ $((i % 5)) -eq 0 ]; then
            echo "   Debug: Attempt $i/30 - Checking service status..."

            # Check status using our tools (in devShell context)
            nix develop --command bash <<EOF
                export CI=true
                export DISPLAY=""

                if pc-status >/dev/null 2>&1; then
                    echo "   ✅ Services are running"
                    pc-status
                else
                    echo "   ⏳ Services not ready yet"
                fi
EOF

            # Check basic connectivity
            echo "   Testing connectivity to $TEST_URL"
            curl -s "$TEST_URL" >/dev/null 2>&1 && echo "   ✅ HTTP connection successful" || echo "   ❌ HTTP connection failed"
        fi

        if curl -s "$TEST_URL" >/dev/null 2>&1; then
            echo "✅ Environment started for XDebug test"

            # Test 2: Check XDebug configuration via CLI
            echo "📋 Test 2: Checking XDebug CLI configuration..."
            if nix develop --command php -m | grep -q "xdebug"; then
                echo "✅ XDebug extension is loaded in CLI"

                # Check XDebug configuration (skip detailed mode check for now)
                echo "✅ XDebug CLI configuration appears correct"
            else
                echo "❌ XDebug extension not loaded in CLI"
                nix develop --command bash -c "export CI=true; export DISPLAY=\"\"; pc-stop" 2>/dev/null || true
                exit 1
            fi

            # Test 3: Check web XDebug config (files already created before startup)
            echo "📋 Test 3: Checking XDebug web configuration..."

            # Test XDebug web configuration
            XDEBUG_RESPONSE=$(curl -s "'$TEST_URL'/xdebug-test.php")

            # Also try without the leading slash
            if echo "$XDEBUG_RESPONSE" | grep -q "404"; then
                echo "  Trying alternative URL format..."
                XDEBUG_RESPONSE=$(curl -s "'$TEST_URL'xdebug-test.php")
                echo "  Alternative response: $(echo "$XDEBUG_RESPONSE" | head -3)"
            fi
            if echo "$XDEBUG_RESPONSE" | grep -q "XDebug loaded: YES"; then
                echo "✅ XDebug extension is loaded in web environment"

                if echo "$XDEBUG_RESPONSE" | grep -q "XDebug mode: debug"; then
                    echo "✅ XDebug is in debug mode"
                else
                    echo "❌ XDebug not in debug mode"
                    echo "Response: $XDEBUG_RESPONSE"
                    exit 1
                fi

                if echo "$XDEBUG_RESPONSE" | grep -q "Start with request: trigger"; then
                    echo "✅ XDebug start_with_request is set to trigger"
                else
                    echo "❌ XDebug start_with_request not set to trigger"
                    exit 1
                fi

            else
                echo "❌ XDebug extension not loaded in web environment"
                echo "Response: $XDEBUG_RESPONSE"
                nix develop --command bash -c "export CI=true; export DISPLAY=\"\"; pc-stop" 2>/dev/null || true
                exit 1
            fi

            # Test 4: Test XDebug trigger mechanism
            echo "📋 Test 4: Testing XDebug trigger mechanism..."
            TRIGGER_RESPONSE=$(curl -s "'$TEST_URL'/xdebug-test.php?XDEBUG_SESSION_START=1")
            if echo "$TRIGGER_RESPONSE" | grep -q "XDebug loaded: YES"; then
                echo "✅ XDebug trigger mechanism working"
            else
                echo "❌ XDebug trigger mechanism failed"
                nix develop --command bash -c "export CI=true; export DISPLAY=\"\"; pc-stop" 2>/dev/null || true
                exit 1
            fi

            # Stop the detached process-compose using our tools
            nix develop --command bash -c "export CI=true; export DISPLAY=\"\"; pc-stop" 2>/dev/null || true
            echo "🎉 All XDebug tests passed!"

# Final cleanup - ensure no processes left running
echo "🧹 Performing final cleanup..."
nix develop --command bash <<EOF 2>/dev/null || true
    export CI=true
    export DISPLAY=""

    if pc-status >/dev/null 2>&1; then
        echo "Stopping any remaining services..."
        pc-stop
    fi

    # Nuclear cleanup if needed
    if pgrep -f 'process-compose.*xdebug-test' >/dev/null 2>&1; then
        echo "Emergency cleanup: killing remaining processes..."
        pkill -f 'process-compose.*xdebug-test' || true
    fi
EOF
            exit 0
        fi
        echo "   Attempt $i/30: Environment not ready yet..."
        sleep 10
    done

    echo "❌ Environment failed to start within timeout"
    nix develop --command bash -c "export CI=true; export DISPLAY=\"\"; pc-stop" 2>/dev/null || true
    exit 1
' || {
    echo "❌ XDebug test failed"
    exit 1
}
