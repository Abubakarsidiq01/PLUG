import { test, expect } from "@playwright/test";

// P1.S1 (P1-TWO.md): public Privacy, Terms and Support route shells. They are
// public, honest placeholders until the final legal text is approved, and they
// must never sit behind the admin redirect.

const routes = [
  { path: "/privacy", heading: "Privacy Policy", title: "Privacy Policy — PLUG" },
  { path: "/terms", heading: "Terms of Service", title: "Terms of Service — PLUG" },
  { path: "/support", heading: "Support", title: "Support — PLUG" },
];

// design/tokens.json target.minTouch.
const MIN_TOUCH = 44;

for (const route of routes) {
  test(`${route.path} is public and renders its own heading and title`, async ({ page }) => {
    const response = await page.goto(route.path);
    expect(response?.status()).toBe(200);
    expect(response?.request().redirectedFrom()).toBeNull();
    await expect(page).toHaveURL(new RegExp(`${route.path}$`));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(route.heading);
    await expect(page).toHaveTitle(route.title);
  });

  test(`${route.path} offers a way back home`, async ({ page }) => {
    await page.goto(route.path);
    await expect(page.getByText(/^Status:/)).toHaveCount(0);
    await page.getByRole("link", { name: "Back to home" }).click();
    await expect(page).toHaveURL(/\/$/);
  });

  test(`${route.path} links are at least ${MIN_TOUCH}px touch targets`, async ({ page }) => {
    await page.goto(route.path);
    const links = [
      page.getByRole("link", { name: "Back to home" }),
      ...(await page.getByRole("navigation", { name: "Information" }).getByRole("link").all()),
    ];
    expect(links.length).toBeGreaterThan(1);
    for (const link of links) {
      const box = await link.boundingBox();
      const name = await link.textContent();
      expect(box, `${name} is not rendered`).not.toBeNull();
      expect(box!.height, `${name} height`).toBeGreaterThanOrEqual(MIN_TOUCH);
      expect(box!.width, `${name} width`).toBeGreaterThanOrEqual(MIN_TOUCH);
    }
  });
}

test("every public page has one shared footer linking all three routes", async ({ page }) => {
  for (const path of ["/", ...routes.map(route => route.path)]) {
    await page.goto(path);
    await expect(page.getByRole("navigation", { name: "Information" }), path).toHaveCount(1);
    await expect(page.getByRole("contentinfo"), path).toHaveCount(1);
  }
  const nav = page.getByRole("navigation", { name: "Information" });
  await expect(nav.getByRole("link", { name: "Privacy", exact: true })).toHaveAttribute("href", "/privacy");
  await expect(nav.getByRole("link", { name: "Terms", exact: true })).toHaveAttribute("href", "/terms");
  await expect(nav.getByRole("link", { name: "Support", exact: true })).toHaveAttribute("href", "/support");
});

// manual.docx Figure 14: every public page carries the same header, whose logo
// links home, and exactly one h1 that is the largest text in the page's main content.
test("the PLUG logo links home and each page has one dominant h1", async ({ page }) => {
  for (const path of ["/", "/admin/login", ...routes.map(route => route.path)]) {
    await page.goto(path);
    const logo = page.getByRole("banner").getByRole("link", { name: "PLUG home" });
    await expect(logo, path).toHaveAttribute("href", "/");
    await expect(page.getByRole("heading", { level: 1 }), path).toHaveCount(1);
    const sizes = await page.evaluate(() => {
      const h1 = parseFloat(getComputedStyle(document.querySelector("main h1")!).fontSize);
      const others = [...document.querySelectorAll("main *:not(h1)")]
        .filter(element => element.childNodes.length && [...element.childNodes].some(node => node.nodeType === 3 && node.textContent!.trim()))
        .map(element => parseFloat(getComputedStyle(element).fontSize));
      return { h1, max: Math.max(...others) };
    });
    expect(sizes.h1, path).toBeGreaterThan(sizes.max);
  }
});

for (const route of routes) {
  test(`${route.path} contains readable starter text and a working contact`, async ({ page }) => {
    await page.goto(route.path);
    await expect(page.getByText(/For private-test review/)).toBeVisible();
    expect(await page.getByRole("heading", { level: 2 }).count()).toBeGreaterThan(3);
    const contact = page.getByRole("link", { name: "Contact PLUG: privacy@plugapp.com" });
    await expect(contact).toHaveAttribute("href", "mailto:privacy@plugapp.com");
    await contact.scrollIntoViewIfNeeded();
    await expect(contact).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  });
}
