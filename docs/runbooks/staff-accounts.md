# Staff accounts: set up, sign in, add and remove people

Staff are the people who run PLUG (ADR-013). Nothing here needs a code change or a QR code.

## First owner, once per environment

1. Put these in `secrets/staff.env` (gitignored, `chmod 600`) or the environment's secret store:

   ```
   PLUG_STAFF_OWNER_EMAIL=you@example.com
   RESEND_API_KEY=re_...            # optional locally; required for real email
   PLUG_STAFF_MAIL_FROM=PLUG <staff@your-verified-domain>
   ```

   Locally, without a Resend key, `tools/run-phase2-local.sh` writes staff mail to
   `backend/build/development-staff-mail.txt` (owner-only) instead of sending it.
   Staging needs `PLUG_STAFF_MAIL_DELIVERY=resend`; with `none` staff sign-in answers 503.
2. Start the server. While no staff account exists, it emails the owner an invitation once.
3. `node tools/staff.mjs accept`, paste the invitation code from the email, choose a password
   (12–64 characters, not easily guessed).
4. `node tools/staff.mjs login`: email, password, then the six-digit code from the email.

The owner email setting does nothing once a staff account exists, so it can stay set.

## Adding and removing people (owner only)

- `node tools/staff.mjs invite partner@example.com staff` (or `owner`). They follow steps 3–4.
- `node tools/staff.mjs list`
- `node tools/staff.mjs disable usr_…`: their sessions end immediately. Inviting them again
  restores them with a new password.

## Signing in day to day

Sessions last 15 minutes and refresh for up to 12 hours; after that, sign in again with a new
code. `node tools/staff.mjs logout` ends the session. Set `PLUG_API_URL` to use another server.

## If something goes wrong

- No email: check `PLUG_STAFF_MAIL_DELIVERY`, the Resend key and the verified sender domain.
- "Too many attempts" (429): wait 15 minutes. Repeated failures appear in `audit_events` as
  `staff.login_failed`, `staff.code_failed` and `staff.rate_limited`.
- A staff mailbox or password is compromised: an owner disables the account at once, then
  re-invites after the mailbox is secured. See `docs/runbooks/leaked-secret.md`.
