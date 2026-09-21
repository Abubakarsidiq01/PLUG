import { defineConfig, devices } from "@playwright/test";

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
    baseURL: process.env.PLUG_WEB_URL ?? "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  webServer: {
    command: process.env.CI
      ? "pnpm --filter @plug/web start"
      : "pnpm --filter @plug/web dev",
    url: "http://127.0.0.1:3000",
    reuseExistingServer: !process.env.CI,
    cwd: "..",
  },
  projects: [
    { name: "mobile", use: { ...devices["iPhone 14"], viewport: { width: 360, height: 800 } } },
    { name: "tablet", use: { ...devices["iPad Mini"], viewport: { width: 768, height: 1024 } } },
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1280, height: 900 } } },
  ],
});
