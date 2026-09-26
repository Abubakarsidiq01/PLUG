import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

for (const route of [
  { path: "/", name: "public-shell" },
  { path: "/admin/login", name: "admin-login" },
  { path: "/terms", name: "terms" },
  { path: "/privacy", name: "privacy" },
  { path: "/support", name: "support" },
]) {
  test(`${route.name} has no automated accessibility violations`, async ({ page }, testInfo) => {
    // Axe analysis plus a full-page screenshot, run across three viewport
    // projects in parallel against one shared dev server, routinely exceeds
    // the default 30s locally on a cold/first-compile hit (the page itself
    // renders fine — see evidence/P0 error-context captures). CI already
    // tolerates this via `retries: 2`; `slow()` gives the same headroom to a
    // local single-shot run instead of masking it with a blanket retry.
    test.slow();
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
