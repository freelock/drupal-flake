#!/usr/bin/env bash
set -euo pipefail

# Test script for nix run .#demo functionality
# This script tests that the demo environment starts correctly

echo "🧪 Testing nix run .#demo functionality..."

# Create test-logs directory for CI artifacts
mkdir -p test-logs

# Set up test environment
export TEST_PROJECT_NAME="test-project"
# Use localhost in CI environments since .ddev.site domains don't resolve
if [ -n "${CI:-}" ] || [ -n "${GITLAB_CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    export TEST_URL="http://localhost:8088"
else
    export TEST_URL="http://test-project.ddev.site:8088"
fi
export TEST_TIMEOUT=600  # 10 minutes timeout for CI

# Ensure we have a clean git state for template testing
if [[ -n $(git status --porcelain) ]]; then
    echo "⚠️  Working directory is dirty, committing changes for testing..."
    git add . 2>/dev/null || true
    git commit -m "WIP: Test commit for CI" 2>/dev/null || true
fi

cleanup() {
    echo "🧹 Cleaning up test environment..."
    # Use killall if pkill is not available (e.g., in CI environments)
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "php-fpm.*test-project" || true
        pkill -f "nginx.*test-project" || true
        pkill -f "mysql.*test-project" || true
    elif command -v killall >/dev/null 2>&1; then
        killall -q php-fpm || true
        killall -q nginx || true
        killall -q mysqld || true
    else
        echo "⚠️  Neither pkill nor killall available, skipping process cleanup"
    fi
    cd .. 2>/dev/null || true
    # Remove from git staging and filesystem
    git reset test-project/ 2>/dev/null || true
    rm -rf test-project/ || true
    rm -f demo.log || true
}

# Cleanup on exit
trap cleanup EXIT

# Test 1: Basic flake evaluation
echo "📋 Test 1: Checking flake evaluation..."
if ! nix flake check 2>&1 | grep -q "error:"; then
    echo "✅ Flake evaluation passed"
else
    echo "❌ Flake evaluation failed"
    exit 1
fi

# Test 2: Template initialization
echo "📋 Test 2: Testing template initialization..."
mkdir -p test-project
cd test-project

# Initialize from template (use the parent directory's template)
nix flake init -t ../ 2>&1 || {
    echo "❌ Template initialization failed"
    exit 1
}

# Add the test project to git so Nix can see it (but don't commit)
cd ..
git add test-project/
cd test-project

echo "✅ Template initialization passed"

# Test 3a: Test start-demo command wrapper
echo "📋 Test 3a: Testing start-demo command wrapper..."
nix develop --command bash <<EOF
    export CI=true
    export DISPLAY=""
    export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
    
    # Test that start-demo command exists and shows help
    if start-demo --help | grep -q "Usage: start-demo"; then
        echo "✅ start-demo command wrapper working"
    else
        echo "❌ start-demo command wrapper broken"
        exit 1
    fi
EOF

# Test 3b: Demo environment startup (with timeout)
echo "📋 Test 3b: Testing demo environment startup..."
# Start demo in detached mode for testing
echo "🔨 Starting demo environment in detached mode (this may take several minutes)..."

# Enter devShell and start demo services  
nix develop --command bash <<EOF
    # Set CI environment variables for headless operation
    export CI=true
    export DISPLAY=""
    export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
    
    echo "Debug: Available commands: \$(which start-demo start-detached pc-status pc-stop 2>/dev/null || echo not found)"
    echo "Debug: TTY check: \$(tty 2>/dev/null || echo 'no tty')"
    echo "Debug: CI=\$CI, DISPLAY=\$DISPLAY"
    echo "Debug: PC_SOCKET_PATH=\$PC_SOCKET_PATH"
    
    # Test both the nix run and start-demo approaches
    echo "Testing via start-demo command (should be equivalent to nix run .#demo)"
    timeout 30 start-demo --help >/dev/null || echo "start-demo help test completed"
    
    # Always use detached mode for testing to avoid TUI issues
    echo "Starting demo in detached mode (no TUI)"
    nix run .#demo -- --detached >../demo.log 2>&1
    
    echo "Demo start process completed"
EOF

# Give it more time to start all services
echo "⏳ Waiting for services to initialize..."
sleep 15

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
for i in {1..30}; do
    # Check status using our process management tools
    if [ $((i % 5)) -eq 0 ]; then
        echo "   Debug: Attempt $i/30 - Checking service status..."
        nix develop --command bash <<EOF
            export CI=true
            export DISPLAY=""
            export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
            
            if pc-status >/dev/null 2>&1; then
                echo "   ✅ Services are running"
                pc-status
            else
                echo "   🔴 Process-compose is not running"
                echo "   Expected socket: \$PC_SOCKET_PATH"
                ls -la /tmp/process-compose* 2>/dev/null || echo "   No process-compose sockets found"
            fi
EOF
    fi
    
    # Check if HTTP service is available
    if curl -s "$TEST_URL" >/dev/null 2>&1; then
        echo "✅ Demo environment started successfully at $TEST_URL"
        
        # Test 4: Test workflow commands (pc-status, pc-attach simulation)
        echo "📋 Test 4: Testing workflow commands..."
        nix develop --command bash <<EOF
            export CI=true
            export DISPLAY=""
            export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
            
            # Test pc-status command
            echo "Testing pc-status..."
            if pc-status | grep -q "Process-compose is running"; then
                echo "✅ pc-status command working"
            else
                echo "❌ pc-status command failed"
                exit 1
            fi
            
            # Test that we can query the REST API (simulate what pc-attach would do)
            echo "Testing REST API connectivity..."
            if curl --silent --max-time 2 --unix-socket "\$PC_SOCKET_PATH" http://localhost/project/state >/dev/null 2>&1; then
                echo "✅ REST API connectivity working (pc-attach would work)"
            else
                echo "⚠️ REST API not responding (pc-attach might have issues)"
            fi
            
            # Test start-detached command directly (alternative startup method)
            echo "Testing start-detached command availability..."
            if command -v start-detached >/dev/null 2>&1; then
                echo "✅ start-detached command available"
            else
                echo "❌ start-detached command missing"
                exit 1
            fi
            
            # Test help system
            echo "Testing help system..."
            if ? | grep -q "Development Commands"; then
                echo "✅ Help system working"
            else
                echo "❌ Help system broken"
                exit 1
            fi
EOF
        
        # Stop the detached process-compose using our tools
        nix develop --command bash <<EOF 2>/dev/null || true
            export CI=true
            export DISPLAY=""
            export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
            pc-stop
EOF
        exit 0
    fi
    
    echo "   Attempt $i/30: Services not ready yet..."
    sleep 10
done

echo "❌ Demo environment failed to start within timeout"
echo "Demo log output:"
cat demo.log 2>/dev/null || echo "No log file found"
# Save logs for CI artifacts
cp demo.log test-logs/demo-timeout.log 2>/dev/null || true

# Stop the detached process-compose using our tools
nix develop --command bash <<EOF 2>/dev/null || true
    export CI=true
    export DISPLAY=""
    export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
    pc-stop
EOF
exit 1

echo "🎉 All demo tests passed!"

# Final cleanup - ensure no processes left running  
echo "🧹 Performing final cleanup..."
nix develop --command bash <<EOF 2>/dev/null || true
    export CI=true
    export DISPLAY=""
    export PC_SOCKET_PATH="/tmp/process-compose-\${PROJECT_NAME:-test-project}.sock"
    
    if pc-status >/dev/null 2>&1; then
        echo "Stopping any remaining services..."
        pc-stop
    fi
    
    # Nuclear cleanup if needed
    if pgrep -f 'process-compose.*test-project' >/dev/null 2>&1; then
        echo "Emergency cleanup: killing remaining processes..."
        pkill -f 'process-compose.*test-project' || true
    fi
    
    # Clean up socket files
    rm -f /tmp/process-compose-*test-project*.sock 2>/dev/null || true
EOF