import { test, expect, type Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

// The staff console with sign-in switched on (ADR-013, contract 0.6.0). Playwright starts a
// second copy of the site on port 3101 with PLUG_API_URL pointing at
// tests/e2e/support/staff-api-stub.mjs, which serves /fixtures. No backend, database or
// email is involved. The closed console on the main test server is covered by the Phase 0
// and Phase 1 specs.
test.skip(!!process.env.PLUG_WEB_URL, "The stand-in API exists only beside the local test servers.");

const site = "http://127.0.0.1:3101";

async function signIn(page: Page, email = "staff@example.com") {
  await page.goto(`${site}/admin/login`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill("stub staff password");
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Enter your code");
  await page.getByLabel("Six-digit code").fill("123456");
  await page.getByRole("button", { name: "Sign in" }).click();
}

test("without a session the console redirects to sign-in and shows no data", async ({ page }) => {
  await page.goto(`${site}/admin`);
  await expect(page).toHaveURL(/\/admin\/login\?from=%2Fadmin/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Staff sign in");
  await expect(page.getByRole("table")).toHaveCount(0);
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
});

test("a forged cookie is refused by the API and ends at sign-in", async ({ page, context }) => {
  await context.addCookies([{ name: "plug_staff_access", value: "forged", domain: "127.0.0.1", path: "/admin" }]);
  await page.goto(`${site}/admin`);
  await expect(page).toHaveURL(/\/admin\/login/);
  await expect(page.getByRole("table")).toHaveCount(0);
  await page.goto(`${site}/admin/users/another-user`);
  await expect(page).toHaveURL(/\/admin\/login\?from=/);
});

test("staff sign in with a password and an emailed code, read live data, and sign out", async ({ page, context, browserName }) => {
  const apiRequests: string[] = [];
  page.on("request", request => {
    if (new URL(request.url()).pathname.startsWith("/v1/")) apiRequests.push(request.url());
  });
  await signIn(page);
  await expect(page).toHaveURL(`${site}/admin`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Classifier inspector");
  await expect(page.getByText("Sample data from the repository fixtures.")).toHaveCount(0);
  for (const name of ["Skill vocabulary", "Vocabulary gaps", "Recent classifications", "Refusals"]) {
    await expect(page.getByRole("region", { name: `${name} table`, exact: true })).toBeVisible();
  }

  // The tokens stay out of reach of page scripts, and the browser never calls the API itself.
  const cookies = await context.cookies(`${site}/admin`);
  for (const name of ["plug_staff_access", "plug_staff_refresh"]) {
    const cookie = cookies.find(item => item.name === name);
    expect(cookie, name).toBeDefined();
    expect(cookie!.httpOnly, name).toBe(true);
    // Playwright's WebKit build for Windows does not report SameSite; Chromium does.
    if (browserName === "chromium") expect(cookie!.sameSite, name).toBe("Strict");
    expect(cookie!.path, name).toBe("/admin");
  }
  expect(await page.evaluate(() => document.cookie)).not.toContain("plug_staff");
  expect(await page.content()).not.toContain("stub-access-staff");
  expect(apiRequests).toEqual([]);

  // Paging: the gaps fixture says more exist, so the console offers the older page.
  await page.getByRole("link", { name: "Older entries" }).click();
  await expect(page).toHaveURL(/\/admin\?gaps=/);
  await expect(page.getByText("No unmatched terms have been recorded.")).toBeVisible();
  await page.getByRole("link", { name: "Back to the newest" }).click();
  await expect(page.getByRole("region", { name: "Vocabulary gaps table", exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByText("You are signed out.")).toBeVisible();
  expect((await context.cookies(`${site}/admin`)).filter(item => item.name.startsWith("plug_staff"))).toEqual([]);
  await page.goto(`${site}/admin`);
  await expect(page).toHaveURL(/\/admin\/login/);
});

test("a wrong password and a wrong code never open the console", async ({ page }) => {
  await page.goto(`${site}/admin/login`);
  await page.getByLabel("Email").fill("staff@example.com");
  await page.getByLabel("Password").fill("not the password");
  await page.getByRole("button", { name: "Continue" }).click();
  // Same next step as a right password: the page does not say which it was.
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Enter your code");
  await page.getByLabel("Six-digit code").fill("123456");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.locator(".form-error")).toContainText("That sign-in ran out.");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Staff sign in");

  await page.getByLabel("Email").fill("staff@example.com");
  await page.getByLabel("Password").fill("stub staff password");
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByLabel("Six-digit code").fill("000000");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.locator(".form-error")).toContainText("That code is not right.");
  await page.goto(`${site}/admin`);
  await expect(page).toHaveURL(/\/admin\/login/);
});

test("a session the API refuses sees the denied notice, a reference and no data", async ({ page }) => {
  await signIn(page, "reader@example.com");
  await expect(page.getByRole("heading", { level: 2, name: "You do not have access" })).toBeVisible();
  await expect(page.getByText(/^Reference: req_/)).toBeVisible();
  await expect(page.getByRole("table")).toHaveCount(0);
});

test("an access token that ran out is refreshed once, without signing in again", async ({ page, context }) => {
  await context.addCookies([
    { name: "plug_staff_access", value: "stub-access-expired", domain: "127.0.0.1", path: "/admin", httpOnly: true, sameSite: "Strict" },
    { name: "plug_staff_refresh", value: "stub-refresh-staff", domain: "127.0.0.1", path: "/admin", httpOnly: true, sameSite: "Strict" },
  ]);
  await page.goto(`${site}/admin`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Classifier inspector");
  await expect(page.getByRole("region", { name: "Refusals table", exact: true })).toBeVisible();
});

test("sign-in says so when the server cannot send email", async ({ page }) => {
  await page.goto(`${site}/admin/login`);
  await page.getByLabel("Email").fill("down@example.com");
  await page.getByLabel("Password").fill("stub staff password");
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.locator(".form-error")).toContainText("Staff sign-in is not available right now");
  await expect(page.locator(".form-error")).toContainText("req_stub-0001");
});

test("an emailed invitation link fills the code, and a password can be chosen", async ({ page }) => {
  await page.goto(`${site}/staff/accept#token=sti_stub-invitation`);
  await expect(page.getByLabel("Invitation code")).toHaveValue("sti_stub-invitation");
  await page.getByLabel("New password").fill("my password is long");
  await page.getByLabel("Repeat the password").fill("my password is long");
  await page.getByRole("button", { name: "Create my staff account" }).click();
  await expect(page.locator(".form-error")).toContainText("too easy to guess");
  await expect(page.getByLabel("Invitation code")).toHaveValue("sti_stub-invitation");
  await page.getByLabel("New password").fill("a long and unusual phrase");
  await page.getByLabel("Repeat the password").fill("a long and unusual phrase");
  await page.getByRole("button", { name: "Create my staff account" }).click();
  await expect(page).toHaveURL(/\/admin\/login\?accepted=1/);
  await expect(page.getByText("Your staff account is ready.")).toBeVisible();
});

test("an owner sees the staff, invites someone and disables someone; the API decides", async ({ page }, testInfo) => {
  const newcomer = `new.person.${testInfo.project.name}@example.com`;
  await signIn(page);
  await page.getByRole("link", { name: "Staff" }).click();
  await expect(page).toHaveURL(`${site}/admin/staff`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Staff");
  const table = page.getByRole("region", { name: "Staff table" });
  await expect(table.getByText("partner@example.com")).toBeVisible();
  await expect(table.getByText("staff@example.com (you)")).toBeVisible();
  // Nobody is offered a way to disable themselves.
  await expect(page.getByRole("button", { name: "Disable staff@example.com" })).toHaveCount(0);

  await page.getByLabel("Email").fill("taken@example.com");
  await page.getByRole("button", { name: "Send invitation" }).click();
  await expect(page.locator(".form-error")).toContainText("already has an active staff account");
  await page.getByLabel("Email").fill(newcomer);
  await page.getByRole("button", { name: "Send invitation" }).click();
  await expect(page.getByRole("status")).toContainText("Invitation sent");

  // The stand-in lists an invited person at once, as if they had accepted.
  await page.getByRole("button", { name: `Disable ${newcomer}` }).click();
  await expect(page.getByRole("status")).toContainText("Their sessions have ended");
  await expect(table.getByRole("row", { name: new RegExp(newcomer.replace(/\./g, "\\.")) })).toContainText("Disabled");
});

test("a staff member the API refuses sees no staff list and no invite form", async ({ page }) => {
  await signIn(page, "reader@example.com");
  await expect(page).toHaveURL(`${site}/admin`);
  await page.goto(`${site}/admin/staff`);
  await expect(page.getByRole("heading", { level: 2, name: "You do not have access" })).toBeVisible();
  await expect(page.getByRole("table")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Send invitation" })).toHaveCount(0);
});

test("the invitation leaves the address bar once read", async ({ page }) => {
  await page.goto(`${site}/staff/accept#token=sti_stub-invitation`);
  await expect(page.getByLabel("Invitation code")).toHaveValue("sti_stub-invitation");
  await expect(page).toHaveURL(`${site}/staff/accept`);
});

for (const [name, path, title] of [
  ["staff-sign-in", "/admin/login", "Admin"],
  ["staff-invitation", "/staff/accept", "Staff invitation"],
  ["staff-console", "/admin", "Classifier inspector"],
  ["staff-people", "/admin/staff", "Staff"],
] as const) {
  test(`${name} has no accessibility violations and no sideways page scroll`, async ({ page }, testInfo) => {
    test.slow();
    if (path === "/admin" || path === "/admin/staff") {
      await signIn(page);
      await expect(page).toHaveURL(`${site}/admin`);
      if (path === "/admin/staff") await page.goto(`${site}${path}`);
    } else await page.goto(`${site}${path}`);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    // After signing in, the new page's title arrives a moment after its heading.
    await expect(page).toHaveTitle(`${title} — PLUG`);
    await page.evaluate(async () => { await document.fonts.ready; });
    const results = await new AxeBuilder({ page }).analyze();
    await testInfo.attach(`${name}-${page.viewportSize()!.width}px`, {
      body: await page.screenshot({ fullPage: true, scale: "css" }),
      contentType: "image/png",
    });
    expect(results.violations).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  });
}

test("the invitation page does not exist on a site without the console", async ({ request }) => {
  expect((await request.get("/staff/accept")).status()).toBe(404);
});
