---
name: drupal-flake-test
description: Set up and run tests on Drupal sites. Configures PHPUnit, Playwright browser testing (cross-platform, no browser download), and CI/CD pipelines. Requires drupal-flake-process skill for environment management.
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

Both Puppeteer and Playwright are supported in `nix develop .#test`. The test shell auto-configures browsers — never run `npx playwright install` or manually download browsers.

**Enter test shell:**
```bash
nix develop .#test
```

**What the test shell provides:**
- Node.js 20
- `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` and `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true`
- `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1`
- Auto-detected browser (see table below)

**Cross-platform browser detection (both Puppeteer and Playwright):**
| Platform | Browser source |
|----------|----------------|
| macOS | Chrome.app / Chromium.app / Edge.app in `/Applications` |
| WSL | Windows Chrome at `/mnt/c/Program Files/Google/Chrome/…` |
| Linux (chromium in PATH) | Uses that Nix-patched binary directly |
| Linux (no system browser) | Falls back to `pkgs.playwright-driver.browsers` from nixpkgs |

**Override the detected browser:**
```bash
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="/path/to/chrome"
# or
export PLAYWRIGHT_BROWSERS_PATH="/path/to/playwright-browsers"
```

### Playwright (Recommended for new tests)

**Quick start:**
```bash
nix develop .#test
playwright-setup          # creates playwright.config.cjs + example test
npm install --save-dev @playwright/test
npx playwright test
npx playwright show-report data/playwright-report
```

`playwright-setup` creates:
- `playwright.config.cjs` — configured for Drupal (baseURL from `SIMPLETEST_BASE_URL`, sequential workers, traces/screenshots on failure)
- `tests/playwright/example.spec.js` — front page, login page, and admin login tests
- `data/playwright-report/` and `data/playwright-results/` output directories

**Example test:**
```javascript
const { test, expect } = require('@playwright/test');

test('admin login', async ({ page }) => {
  await page.goto('/user/login');
  await page.fill('#edit-name', 'admin');
  await page.fill('#edit-pass', 'admin');
  await page.click('#edit-submit');
  await expect(page).toHaveURL(/\/user\/\d+/);
});
```

**Version pinning:** `pkgs.playwright-driver.browsers` from nixpkgs may not match your `@playwright/test` npm version. For exact alignment use one of these community flakes:
- [`halfwhey/nix-playwright-nightly`](https://github.com/halfwhey/nix-playwright-nightly) — Linux + macOS (arm64), Cachix binary cache, nightly CI builds
- [`pietdevries94/playwright-web-flake`](https://github.com/pietdevries94/playwright-web-flake) — Linux, version-tagged releases (`nix shell github:pietdevries94/playwright-web-flake/1.50.0#playwright-test`)

### Puppeteer

```bash
nix develop .#test
npm init -y
npm install puppeteer

cat > tests/example.test.js << 'EOF'
const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  await page.goto(process.env.SIMPLETEST_BASE_URL || 'http://localhost:8088');
  console.log(await page.title());
  await browser.close();
})();
EOF
node tests/example.test.js
```

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
        
      - name: Browser tests (Playwright)
        run: |
          nix develop .#test -c bash -c "
            npm ci
            npx playwright test
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
    - nix develop .#test -c bash -c "npm ci && npx playwright test"
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
