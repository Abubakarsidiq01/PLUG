import { test, expect } from "@playwright/test";

// P1.S1 (P1-TWO.md): public Privacy, Terms and Support route shells. They are
// public, honest placeholders until the final legal text is approved, and they
// must never sit behind the admin redirect.

const routes = [
  { path: "/privacy", heading: "Privacy Policy", title: "Privacy Policy — PLUG" },
  { path: "/terms", heading: "Terms & Conditions", title: "Terms & Conditions — PLUG" },
  { path: "/support", heading: "Support", title: "Support — PLUG" },
];

for (const route of routes) {
  test(`${route.path} is public and renders its own heading and title`, async ({ page }) => {
    const response = await page.goto(route.path);
    expect(response?.status()).toBe(200);
    expect(response?.request().redirectedFrom()).toBeNull();
    await expect(page).toHaveURL(new RegExp(`${route.path}$`));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(route.heading);
    await expect(page).toHaveTitle(route.title);
  });

  test(`${route.path} says the final text is pending and offers a way back`, async ({ page }) => {
    await page.goto(route.path);
    await expect(page.getByText("Status: placeholder. Final wording is pending approval.")).toBeVisible();
    await page.getByRole("link", { name: "Back to home" }).click();
    await expect(page).toHaveURL(/\/$/);
  });
}

test("the home page links to all three routes", async ({ page }) => {
  await page.goto("/");
  const nav = page.getByRole("navigation", { name: "Legal and support" });
  await expect(nav.getByRole("link", { name: "Privacy Policy" })).toHaveAttribute("href", "/privacy");
  await expect(nav.getByRole("link", { name: "Terms & Conditions" })).toHaveAttribute("href", "/terms");
  await expect(nav.getByRole("link", { name: "Support" })).toHaveAttribute("href", "/support");
});
