# ADR-013: Staff accounts, by invitation, with an emailed code

- Status: Accepted by the project owner on 2026-10-05 (option B: "so that I won't have to add
  a line of code for each staff and be scanning QR code"; second factor: emailed code).
  Contract 0.6.0; needs Person Two's approval of the pull request like any contract change.
- Amends: ADR-006 (adds the `staff` account type) and the Phase 1 note in `AccountType` that no
  account holds the admin scope. Recorded in the manual's §27.3 Phase 2 amendments.

## Context

`/v1/admin/**` has required the admin scope plus a completed second factor since Phase 1, and
the P2-TWO.S12 inspection routes were built behind it. No identity could ever hold that scope,
so every caller was refused. "Staff" means the people who run PLUG (the owner, the partner and
anyone they add later), never providers or customers.

Options considered: (A) an allow-list of customer accounts in configuration, edited per person;
(B) separate staff accounts created by invitation; (C) an external identity provider. The owner
chose B with an emailed code, rejecting authenticator-app QR codes.

## Decision

1. **A staff account is its own account**, `users.account_type = 'staff'`, holding the `admin`
   scope and nothing else. It cannot ask, offer or act as a customer, and the customer sign-in
   routes never issue it. Sessions, refresh, logout and revocation are the ordinary ones; a
   staff refresh window is at most 12 hours.
2. **Nobody is added in code.** The first owner is invited once from configuration
   (`PLUG_STAFF_OWNER_EMAIL`, acted on at start-up only while no staff account exists and no
   invitation to it is open). Every later person is invited by an owner:
   `POST /v1/admin/staff/invites`. An invitation is a single-use emailed token, stored hashed,
   valid 72 hours, replaced by any newer invitation to the same address.
3. **Sign-in is two steps.** `POST /v1/staff/login` (email + password) emails a six-digit code;
   `POST /v1/staff/login/verify` exchanges it for a session with the second factor set. The
   first step answers the same 202 whether the email is unknown, the password wrong, or both
   right, and compares against a decoy hash when the email is unknown.
4. **Roles:** `owner` may invite and disable; `staff` may only read. Disabling revokes every
   session at once; an owner cannot disable themselves; a new invitation restores a person.
5. **Mail:** `none` (default; staff sign-in answers 503 `dependency_unavailable`),
   `development` (owner-only local file, refused unless `plug.environment=local`), or `resend`
   (`RESEND_API_KEY`, `PLUG_STAFF_MAIL_FROM`). No code or invitation is ever logged.

## Controls

- Passwords: BCrypt cost 12; 12–64 characters within BCrypt's 72 bytes; refused when trivially
  guessable (few distinct characters, contains "password"/"plug"/the email's name).
- Limits: 5 sign-ins per email and 20 per address per 15 minutes; 5 code attempts per
  challenge, kept on the row so a rollback or restart does not refund them; codes live 10 minutes.
- Audit: bootstrap, invite, join, code sent, code failed, sign-in, disable and every staff
  list read (`admin.read`).

## Consequences

- The inspection API and the coming web inspector are usable by real staff.
- Staff email addresses are stored readable (codes must reach them); they appear only in
  staff-only responses that are never cached.
- Email is a weaker second factor than a passkey or authenticator app: it protects against a
  leaked password but not a compromised mailbox. Staff should use a mailbox with its own MFA.
  Passkeys can replace the emailed code later without changing the account model.
- Until the web console exists, `node tools/staff.mjs` performs accept, login, list, invite,
  disable and logout against any PLUG server.
