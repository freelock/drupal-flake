#!/usr/bin/env bash
set -euo pipefail

# Test script for nix run .#demo functionality
# This script tests that the demo environment starts correctly

echo "🧪 Testing nix run .#demo functionality..."

# Create test-logs directory for CI artifacts
mkdir -p test-logs

# Set up test environment
export TEST_PROJECT_NAME="test-project"
export TEST_URL="http://test-project.ddev.site:8088"
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

# Test 3: Demo environment startup (with timeout)
echo "📋 Test 3: Testing demo environment startup..."
# Start demo in detached mode for testing
echo "🔨 Starting nix run .#demo in detached mode (this may take several minutes)..."
# Debug: Check if process-compose is available
echo "Debug: process-compose version: $(process-compose --version 2>/dev/null || echo not found)"
echo "Debug: process-compose location: $(which process-compose 2>/dev/null || echo not found)"

# Start the services
nix run .#demo -- --detached >demo.log 2>&1

# Give it more time to start all services
echo "⏳ Waiting for services to initialize..."
sleep 15

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
for i in {1..30}; do
    # Check if HTTP service is available
    if curl -s "$TEST_URL" >/dev/null 2>&1; then
        echo "✅ Demo environment started successfully at $TEST_URL"
        
        # Stop the detached process-compose
        nix run .#demo -- down 2>/dev/null || true
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

# Stop the detached process-compose
nix run .#demo -- down 2>/dev/null || true
exit 1

echo "🎉 All demo tests passed!"