import { defineConfig, devices } from "@playwright/test";

// An explicit URL means test that deployment without starting an unrelated
// localhost server. Local runs own their server, so a stale process cannot make
// tests pass against an older build. Use a separate port from interactive dev.
const externalURL = process.env.PLUG_WEB_URL;
const localURL = "http://127.0.0.1:3100";

// Test files live in /tests/e2e per manual.docx §17.3 ("tests/e2e — Playwright,
// three viewports"); this config lives in web/ because the runner is wired
// through the web workspace (`pnpm --filter @plug/web test:e2e`).
export default defineConfig({
  testDir: "../tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: [["html", { open: "never" }]],
  use: {
    baseURL: externalURL ?? localURL,
    trace: "on-first-retry",
  },
  webServer: externalURL ? undefined : {
    command: process.env.CI
      ? "pnpm --filter @plug/web start --hostname 127.0.0.1 --port 3100"
      : "pnpm --filter @plug/web dev --hostname 127.0.0.1 --port 3100",
    url: localURL,
    reuseExistingServer: false,
    cwd: "..",
    // Opens /preview/admin, which draws the fixtures only. /admin stays closed.
    env: { PLUG_ADMIN_PREVIEW: "fixtures" },
  },
  projects: [
    { name: "mobile", use: { ...devices["iPhone 14"], viewport: { width: 360, height: 800 } } },
    { name: "tablet", use: { ...devices["iPad Mini"], viewport: { width: 768, height: 1024 } } },
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1280, height: 900 } } },
  ],
});
