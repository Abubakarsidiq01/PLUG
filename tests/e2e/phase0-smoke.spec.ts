import { test, expect } from "@playwright/test";

// Phase 0 baseline (manual.docx P0.S4 / P0-TWO.md): the public shell loads,
// and the protected admin route redirects when unauthenticated. Runs across
// the mobile/tablet/desktop projects declared in web/playwright.config.ts.

test("public shell loads and states its purpose honestly", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Ask for what you need. Get real, verified availability back."
  );
});

test("an unauthenticated request to /admin is redirected, never rendered", async ({ page }) => {
  const response = await page.goto("/admin");
  expect(response?.request().redirectedFrom()).not.toBeNull();
  await expect(page).toHaveURL(/\/admin\/login\?from=%2Fadmin/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Admin access is not available yet");
});

test("/admin/login itself does not redirect", async ({ page }) => {
  const response = await page.goto("/admin/login");
  expect(response?.status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/login$/);
});

test("a forged session cookie cannot unlock the admin shell", async ({ page, context, baseURL }) => {
  await context.addCookies([
    { name: "plug_admin_session", value: "forged", url: baseURL! },
  ]);
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/admin\/login\?from=%2Fadmin/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Admin access is not available yet");
});

test("login-prefixed paths are still protected", async ({ page }) => {
  await page.goto("/admin/login-bypass");
  await expect(page).toHaveURL(/\/admin\/login\?from=%2Fadmin%2Flogin-bypass/);
});
