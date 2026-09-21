import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

for (const route of [
  { path: "/", name: "public-shell" },
  { path: "/admin/login", name: "admin-login" },
]) {
  test(`${route.name} has no automated accessibility violations`, async ({ page }, testInfo) => {
    await page.goto(route.path);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await page.evaluate(async () => { await document.fonts.ready; });

    const results = await new AxeBuilder({ page }).analyze();
    await testInfo.attach("axe-results", {
      body: JSON.stringify(results, null, 2),
      contentType: "application/json",
    });
    await testInfo.attach(`${route.name}-${page.viewportSize()!.width}px`, {
      body: await page.screenshot({ fullPage: true, scale: "css" }),
      contentType: "image/png",
    });

    expect(results.violations).toEqual([]);
  });
}
