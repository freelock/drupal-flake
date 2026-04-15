---
name: drupal-flake-test
description: Set up and run tests on Drupal sites. Configures PHPUnit, browser testing with Puppeteer/Playwright, and CI/CD pipelines. Requires drupal-flake-process skill for environment management.
compatibility: opencode
metadata:
  framework: Drupal
  primary_tool: drupal-flake
  secondary_tools: [phpunit, puppeteer, playwright, github-actions]
  features: [phpunit, browser-testing, ci-cd, test-automation]
  requires: [drupal-flake-process]
---

## Prerequisites

**Ensure environment is running first (see drupal-flake-process skill):**
```bash
# Auto-detection
if ls /tmp/process-compose-*.sock 2>/dev/null | grep -q ""; then
  BASE_URL="http://$(grep DOMAIN .env 2>/dev/null | cut -d= -f2):$(grep PORT .env 2>/dev/null | cut -d= -f2)"
  echo "Environment active: $BASE_URL"
else
  echo "Start with: nix develop && start-detached"
fi
```

## PHPUnit Setup

### Method 1: phpunit-setup (Recommended)
```bash
nix develop
phpunit-setup
```
Creates `phpunit.xml` with SQLite database for isolation.

### Method 2: Module-specific
```bash
# For testing a specific module
phpunit-module <module-name>
# Creates phpunit.<module-name>.xml
```

### Method 3: Custom configuration
```bash
phpunit-custom
# Interactive setup with custom paths
```

### Running Tests
```bash
# All tests
xphpunit

# Specific test class
xphpunit --filter MyTestClass

# Specific module
xphpunit --configuration phpunit.custom.xml
```

**XDebug for PHPUnit:**
- XDebug runs on port 9003
- Trigger with `xphpunit` (pre-configured)
- Or add `?XDEBUG_PROFILE=1` to any URL

## Browser Testing

### Puppeteer (Recommended)

**Enter test shell:**
```bash
nix develop .#test
```

**What's available:**
- Node.js 20
- `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1` (uses system Chrome)
- Auto-detected `PUPPETEER_EXECUTABLE_PATH`

**Cross-platform Chrome detection:**
| Platform | Checked paths |
|----------|---------------|
| Linux | `google-chrome-stable`, `chromium-browser`, `chromium`, `/snap/bin/chromium` |
| macOS | `/Applications/Google Chrome.app`, `/Applications/Chromium.app` |
| WSL | `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe` |

**Quick start:**
```bash
nix develop .#test
npm init -y
npm install puppeteer vitest

# Create tests/example.test.js
cat > tests/example.test.js << 'EOF'
import { test, expect } from 'vitest';
import puppeteer from 'puppeteer';

test('homepage loads', async () => {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  await page.goto('http://localhost:8080');
  expect(await page.title()).toContain('Drupal');
  await browser.close();
});
EOF

# Add to package.json and run
npm pkg set scripts.test="vitest"
npm test
```

**Manual Chrome path:**
```bash
export PUPPETEER_EXECUTABLE_PATH="/path/to/chrome"
```

### Why NOT Playwright?

Nix purity conflicts with Playwright's browser downloads. It tries to download browsers to the store (read-only). **Use Puppeteer instead** - it uses system browsers with `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1`.

### Browser Test Examples

**Login flow:**
```javascript
const page = await browser.newPage();
await page.goto('http://localhost:8080/user/login');
await page.type('#edit-name', 'admin');
await page.type('#edit-pass', 'password');
await page.click('#edit-submit');
await page.waitForSelector('.toolbar-menu');
```

**Visual regression:**
```javascript
await page.screenshot({ path: 'homepage.png', fullPage: true });
```

## CI/CD Templates

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - uses: DeterminateSystems/magic-nix-cache-action@v2
      
      - name: Start environment
        run: |
          nix develop -c start-detached
          sleep 30
          
      - name: Wait for site
        run: |
          until curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; do
            sleep 10
          done
          
      - name: Run PHPUnit
        run: nix develop -c xphpunit
        
      - name: Browser tests
        run: |
          nix develop .#test -c bash -c "
            npm ci
            npm test
          "
```

### GitLab CI

```yaml
# .gitlab-ci.yml
test:
  image: nixos/nix:latest
  before_script:
    - nix develop -c start-detached
    - sleep 30
  script:
    - nix develop -c xphpunit
    - nix develop .#test -c npm test
```

## Test Database Management

**PHPUnit uses SQLite by default** (isolated, fast).

**For MySQL tests:**
```bash
# Create test DB
drush sql:create --db-url='mysql://root@localhost/test'

# Or in phpunit.xml
<env name="SIMPLETEST_DB" value="mysql://root@localhost/test"/>
```

**Reset test data:**
```bash
# SQLite (default)
rm web/sites/simpletest/ -rf

# MySQL
drush sql:drop --db-url='mysql://root@localhost/test' -y
```

## Headless Testing Tips

**Fast feedback loop:**
```bash
# Watch mode
npm test -- --watch

# Specific test
npm test -- tests/login.test.js
```

**Debug mode:**
```javascript
// Add to test
await page.evaluate(() => debugger);

# Or run non-headless
const browser = await puppeteer.launch({ headless: false });
```

**Screenshots on failure:**
```javascript
// In test framework setup
afterEach(async () => {
  if (testFailed) {
    await page.screenshot({ path: `failed-${testName}.png` });
  }
});
```

## Integration with Process Skill

**Always check environment first:**
```bash
# From drupal-flake-process skill
pc-status 2>/dev/null || start-detached

# Then run tests
xphpunit
```
