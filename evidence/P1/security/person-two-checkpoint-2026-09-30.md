# G1 connected checkpoint — Person Two's scope, 2026-09-30

Person Two (`@uzom-a`) ran these checks from her own Windows 11 PC, over the internet,
against the API and web tunnels Person One was running (ADR-004 cloudflared Quick
Tunnels). The tunnel URLs were temporary and have not been recorded as standing
hosts. No credentials were exchanged; only the two origins were shared.

| Item | Value |
|---|---|
| Date | 2026-09-30, about 19:29 UTC |
| Tester's checkout | `main` at `81fd0e2` (Merge PR #31) |
| API origin | cloudflared Quick Tunnel (temporary) |
| Web origin | cloudflared Quick Tunnel (temporary) |
| Backend `/health` | `{"status":"UP","version":"0.0.1-SNAPSHOT","commit":"dev"}` |
| Backend commit and profile | **To be added by Person One.** `/health` reports `dev`, so the commit under test and the active profile (`db` or `staging`) are recorded separately, as the checkpoint instructions require. |
| Bruno CLI | 4.1.0 (`tools/bruno`, locked) |

## 1. API authorization — Bruno `auth` folder

```powershell
cd tests/api
..\..\tools\bruno\node_modules\.bin\bru.cmd run auth --env local --env-var "baseUrl=<API tunnel>"
```

**PASS: 16/16 requests, 31/31 assertions** (4.6 s).

| Request | Result | What it shows |
|---|---|---|
| 01-guest | 201, `guest` | A guest account and session are issued |
| 02-me | 200, `guest` | The guest's access token reads its own account |
| 03-guest-restricted | 403 `forbidden` | A guest cannot use member-only session management |
| 04-admin-refused | 403 `forbidden` | A guest cannot reach admin routes |
| 05-rotate | 200 | Refresh rotates the session |
| 06-replay | 401 `unauthenticated` | Replaying a rotated refresh token is refused |
| 07-replay-revokes-access | 401 | …and the replay revokes the access token |
| 08-replay-revokes-refresh | 401 | …and the rest of the refresh chain |
| 09-logout-guest | 201 | A fresh guest session for the logout cases |
| 10-logout | 204 | Logout succeeds |
| 11-logout-revokes-access | 401 | The access token stops working immediately, server-side |
| 12-logout-revokes-refresh | 401 | The refresh token stops working too |
| 13-anonymous | 401 | No token, no access |
| 14-invalid-apple | 401 | A forged Apple identity token is refused |
| 15-unknown-challenge | 400, detail `expired` | An unknown phone challenge is refused |
| 16-unknown-consent | 400, field `consent_version` | An unpublished consent version is refused |

The runner prints only statuses and assertion results. No access or refresh token,
response body or phone code was printed, recorded or committed.

**Environment note:** `--env staging` failed before sending any request, because
Bruno CLI 4.1 rejects the `#` comment lines that were in `environments/staging.bru`.
The run used `--env local` with `baseUrl` overridden to the API tunnel, which sends
the same requests to the same origin. `staging.bru` is fixed in the same change as
this record (the comments moved to `environments/README.md`), and a
`--env staging` request to the tunnel's `/health` then passed.

## 2. External web headers

```powershell
curl.exe -sSI <web tunnel>/privacy
```

`HTTP/1.1 200 OK`, and the page is the intended one (`<title>Privacy Policy | PLUG</title>`,
`<h1>Privacy Policy</h1>`).

| Header | Value | Result |
|---|---|---|
| `Strict-Transport-Security` | `max-age=31536000` | present |
| `content-security-policy` | `frame-ancestors 'none'; object-src 'none'; base-uri 'self'; form-action 'self'` | present |
| `x-frame-options` | `DENY` | present |
| `x-content-type-options` | `nosniff` | present |
| `referrer-policy` | `strict-origin-when-cross-origin` | present |
| `permissions-policy` | `camera=(), microphone=(), geolocation=()` | present |
| `x-powered-by` | — | absent, as intended |

Observations, none blocking:
- The CSP restricts framing, plugins, base URI and form targets. It does not yet
  restrict script, style or connect sources. Consider a fuller policy before launch.
- `X-Robots-Tag: none` is sent (twice) through the tunnel, so the page is not indexed
  there. That suits a temporary test origin, but `docs/design/figma-implementation-checklist.md`
  marks `/privacy` as indexed. Confirm the production origin does not send it.

## Not covered by Person Two's scope

- Real Apple sign-in and real SMS delivery, which are deferred (ADR-008).
- Controlled rate-limit and abuse runs, which Person One records on isolated test accounts.
- Matching the phone's request ID to the backend log, and the phone-side logout,
  guest and Google behaviour, which Person One records with the phone.
- Account A → account B session access (BOLA/IDOR). It is covered by the backend
  test suite, but the `auth` folder does not exercise it against the tunnel.

## Sign-off — Person Two

I reviewed these sanitized results for my scope: the API authorization checks and the
external web headers above, run from my own PC against the shared tunnels.

**I approve.** — Person Two, Uzoma Stephanie-Portia Okey-Anyanwu (`@uzom-a`), 2026-09-30

Person One signs their own scope separately. This approval does not sign G1 on its own.
