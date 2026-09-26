import { test, expect } from "@playwright/test";

test("information pages resolve from the shared navigation", async ({ page }) => {
  await page.goto("/");
  for (const [label, heading] of [["Terms", "Terms of Service"], ["Privacy", "Privacy Policy"], ["Support", "Support"]]) {
    await page.getByRole("navigation", { name: "Information" }).getByRole("link", { name: label, exact: true }).click();
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(heading);
  }
});

test("admin rejection never requests backend data or accepts forged roles", async ({ page, context, baseURL }) => {
  const apiRequests: string[] = [];
  page.on("request", request => {
    if (new URL(request.url()).pathname.startsWith("/v1/")) apiRequests.push(request.url());
  });
  await context.addCookies([{ name: "plug_admin_session", value: "admin.mfa_verified.true", url: baseURL! }]);
  await page.goto("/admin/users/another-user");
  await expect(page).toHaveURL(/\/admin\/login\?from=/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Admin access is not available yet");
  expect(apiRequests).toEqual([]);
  await expect(page.locator("input")).toHaveCount(0);
});

test("public pages return browser security headers without configuration leaks", async ({ request }) => {
  const response = await request.get("/privacy");
  const headers = response.headers();
  expect(headers["x-content-type-options"]).toBe("nosniff");
  expect(headers["x-frame-options"]).toBe("DENY");
  expect(headers["content-security-policy"]).toContain("frame-ancestors 'none'");
  expect(headers["referrer-policy"]).toBe("strict-origin-when-cross-origin");
  expect(headers["x-powered-by"]).toBeUndefined();
  expect(await response.text()).not.toMatch(/PLUG_DATABASE_PASSWORD|PLUG_IDENTITY_PEPPER|prt_[A-Za-z0-9_-]+/);
});
