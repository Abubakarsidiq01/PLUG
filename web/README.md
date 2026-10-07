# PLUG web

Person Two owns this Next.js public site and protected admin shell. Read
`PROJECT_STATE.json` and `docs/phases/P2-TWO.md` before making changes.
The current site includes the home, Terms, Privacy and Support pages and the staff
console under `/admin`, which is closed unless the server is given `PLUG_API_URL`.
Phase 2 request screens belong to iOS.

From the repository root with Node 22 and pnpm 9.15.9:

```sh
pnpm install --frozen-lockfile
pnpm --filter @plug/web typecheck
pnpm --filter @plug/web lint
pnpm --filter @plug/web test:unit
pnpm --filter @plug/web build
pnpm --filter @plug/web exec playwright install chromium webkit
pnpm --filter @plug/web test:e2e
```

`typecheck` generates Next route types before invoking TypeScript, so it works
without a prior build. `test:unit` runs the shared static fixture and intent-data
checks (`pnpm test:contracts`); it does not prove the future backend extractor.

Playwright covers 360, 768 and 1280 pixel viewports, legal navigation, admin denial,
staff sign-in, security headers and automated accessibility. It starts a dedicated
server on `127.0.0.1:3100`, using a production build when `CI=true`; it never reuses
an unrelated server. For the staff console it also starts a stand-in API on port 3102
(`tests/e2e/support/staff-api-stub.mjs`, which serves `/fixtures`) and a second,
production-built copy of the site on port 3101 that points at it, so the first local run
includes one `next build`. Set `PLUG_WEB_URL` explicitly to test an existing deployment
without starting a local server. In PowerShell, set environment variables using
`$env:CI = "true"` or `$env:PLUG_WEB_URL = "https://your-current-web-deployment"`.

## Staff console

`src/app/_components/admin-inspector.tsx` draws the staff view of the skill vocabulary,
vocabulary gaps, recent classifications and refusals (manual v4 P2-TWO.S12). It takes data
as props and never fetches.

`/admin` shows that view with live data to signed-in staff (ADR-013, contract 0.6.0). It is
closed unless the web server has `PLUG_API_URL`, the origin of the PLUG API. The value must
be HTTPS, or plain HTTP to the same machine for local work; anything else counts as not
set. Without it `/admin/login` shows the "not available" notice, `/staff/accept` is 404 and
nothing asks for a password.

- `/admin/login`: email and password, then the six-digit code the API emails.
- `/staff/accept`: where an emailed invitation lands. Set the backend's
  `PLUG_STAFF_CONSOLE_URL` to this site's origin so the emailed link opens it.
- `/admin`: the inspector, with paging and Sign out.

The browser never holds a token and never calls the API. The session is kept in two
HttpOnly, SameSite=Strict cookies scoped to `/admin`, and the web server calls the API with
the access token. The API stays the authorization boundary: it checks the token, the admin
scope and the second factor on every read, and the page shows only what it returns. A 403
shows the denied notice; a session that ran out is refreshed once, then sent to sign-in.
Inviting and disabling staff are still done with `node tools/staff.mjs`.

To try it on your own PC, start the backend with `PLUG_STAFF_MAIL_DELIVERY=development`
(see `docs/runbooks/staff-accounts.md`), then:

```powershell
$env:PLUG_API_URL = "http://127.0.0.1:18080"
pnpm --filter @plug/web dev
# http://localhost:3000/admin
```

## Admin inspector preview

To review the page without a backend, the route `/preview/admin` draws the synthetic
fixtures in `/fixtures/admin.*`. It answers 404 unless the server has
`PLUG_ADMIN_PREVIEW=fixtures`, it calls no API and it is not indexed. Never set that
variable on a deployed site. Playwright sets it for its own local server.

```powershell
$env:PLUG_ADMIN_PREVIEW = "fixtures"
pnpm --filter @plug/web dev
# http://localhost:3000/preview/admin
# add ?state=empty, ?state=loading, ?state=denied or ?state=unavailable
```

The page's types come from the contract. After any change to `contracts/openapi.yaml`, run
`pnpm --filter @plug/web generate:api` and commit `src/generated/api.ts`.

Interactive development uses `pnpm --filter @plug/web dev` on port 3000. The site
bundles Public Sans locally and reads the shared generated design tokens. Preserve
existing legal branding. Admin routes fail closed without `PLUG_API_URL`; a cookie or
fixture is never authentication.
