# PLUG web

Person Two owns this Next.js public site and protected admin shell. Read
`PROJECT_STATE.json` and `docs/phases/P2-TWO.md` before making changes.
The current site includes the home, Terms, Privacy, Support and unavailable-admin
pages. Phase 2 request screens belong to iOS; an internal web inspector is optional
only when QA needs one and real authenticated endpoints exist.

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
security headers and automated accessibility. It starts a dedicated
server on `127.0.0.1:3100`, using a production build when `CI=true`; it never reuses
an unrelated server. Set `PLUG_WEB_URL` explicitly to test an existing deployment
without starting a local server. In PowerShell, set environment variables using
`$env:CI = "true"` or `$env:PLUG_WEB_URL = "https://your-current-web-deployment"`.

## Admin inspector preview

`src/app/_components/admin-inspector.tsx` draws the staff view of the skill vocabulary,
vocabulary gaps, recent classifications and refusals (manual v4 P2-TWO.S12). It takes data
as props and never fetches.

Staff sign-in does not exist yet, so `/admin` stays closed. To review the page, the route
`/preview/admin` draws the synthetic fixtures in `/fixtures/admin.*`. It answers 404 unless
the server has `PLUG_ADMIN_PREVIEW=fixtures`, it calls no API and it is not indexed. Never
set that variable on a deployed site. Playwright sets it for its own local server.

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
existing legal branding. Admin routes fail closed until real enrollment and MFA
exist; a cookie or fixture is never authentication.
