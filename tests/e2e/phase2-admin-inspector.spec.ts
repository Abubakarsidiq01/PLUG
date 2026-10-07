import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

// The preview draws /fixtures/admin.* only and opens with PLUG_ADMIN_PREVIEW=fixtures,
// which the local Playwright server sets. A deployed site answers 404 for it.
test.skip(!!process.env.PLUG_WEB_URL, "The admin preview exists only on the local test server.");

const preview = "/preview/admin";

test("the preview shows all four fixture tables and says it is sample data", async ({ page }) => {
  const apiRequests: string[] = [];
  page.on("request", request => {
    if (new URL(request.url()).pathname.startsWith("/v1/")) apiRequests.push(request.url());
  });
  const response = await page.goto(preview);
  expect(response?.status()).toBe(200);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Classifier inspector");
  await expect(page.getByText("Sample data from the repository fixtures.")).toBeVisible();
  for (const name of ["Skill vocabulary", "Skills in providers' own words", "Vocabulary gaps", "Recent classifications", "Refusals"]) {
    await expect(page.getByRole("region", { name: `${name} table`, exact: true })).toBeVisible();
  }
  await expect(page.getByRole("region", { name: "Skill vocabulary table", exact: true }).getByRole("row")).toHaveCount(4);
  await expect(page.getByRole("cell", { name: "Awaiting clarification" })).toBeVisible();
  await expect(page.getByRole("cell", { name: "Not classified" })).toBeVisible();
  await expect(page.getByRole("cell", { name: "stalking_tracking" })).toBeVisible();
  expect(apiRequests).toEqual([]);
  // Scoped to the page content: the dev server adds its own tools button outside it.
  await expect(page.locator("#main").locator("input, form, button")).toHaveCount(0);
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
});

test("gap terms stay hidden until opened and paging is stated honestly", async ({ page }) => {
  await page.goto(preview);
  const gaps = page.getByRole("region", { name: "Vocabulary gaps table", exact: true });
  await expect(gaps.getByText("chimney sweeping")).toBeHidden();
  await gaps.getByText("Show term").first().click();
  await expect(gaps.getByText("chimney sweeping")).toBeVisible();
  await expect(page.getByText("More entries exist beyond this page.")).toHaveCount(1);
});

for (const [state, heading] of [
  ["denied", "You do not have access"],
  ["unavailable", "The inspector could not load"],
] as const) {
  test(`the ${state} state shows a notice, a reference and no data`, async ({ page }) => {
    await page.goto(`${preview}?state=${state}`);
    await expect(page.getByRole("heading", { level: 2, name: heading })).toBeVisible();
    await expect(page.getByText(/^Reference: req_/)).toBeVisible();
    await expect(page.getByRole("table")).toHaveCount(0);
  });
}

test("the empty and loading states render without tables", async ({ page }) => {
  await page.goto(`${preview}?state=empty`);
  await expect(page.getByText("No skills are listed.")).toBeVisible();
  await expect(page.getByText("No asks have been refused.")).toBeVisible();
  await expect(page.getByRole("table")).toHaveCount(0);
  await page.goto(`${preview}?state=loading`);
  await expect(page.getByRole("status")).toHaveText("Loading the inspector.");
});

test("the preview has no accessibility violations and no sideways page scroll", async ({ page }, testInfo) => {
  test.slow();
  await page.goto(preview);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await page.evaluate(async () => { await document.fonts.ready; });
  const results = await new AxeBuilder({ page }).analyze();
  await testInfo.attach(`admin-inspector-${page.viewportSize()!.width}px`, {
    body: await page.screenshot({ fullPage: true, scale: "css" }),
    contentType: "image/png",
  });
  expect(results.violations).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test("the real admin console stays closed while the preview is open", async ({ page }) => {
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/admin\/login\?from=/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Admin access is not available yet");
});
