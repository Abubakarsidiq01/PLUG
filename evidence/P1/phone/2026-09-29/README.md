# Physical iPhone evidence received 2026-09-29

The owner supplied IMG_4302 through IMG_4306 and reported that the requested
Google sign-in, force-close/reopen, logout and guest flow worked. This is owner
acceptance of that flow; still images independently establish the states below,
not every intervening interaction. The screenshots show 10:40-10:41; the matching
backend log timestamps are September 28, 2026, America/Chicago.

## Observed states

- IMG_4302: Engineering connected; request ID
  `req_bd313eff-8e15-425f-b6cf-446f23c418fe` matches GET /health HTTP 200 in the backend.
- IMG_4303: Profile shows Google and consent version 2026-09-01. The original
  includes a personal email notification and is kept out of GitHub pending
  sanitization. Its source hash is recorded in provenance.json.
- IMG_4304: Full welcome screen, logo, signup/signin/guest entrypoints and
  Terms/Privacy/Help links. Consistent with returning to the signed-out flow.
- IMG_4305: Engineering connected again; request ID
  `req_a5a78bba-94de-4aad-b36d-0eec5f18d954` matches GET /health HTTP 200 in the backend.
- IMG_4306: Profile shows Guest, consent version 2026-09-01 and the account
  creation/sign-in action with the explicit no-merge explanation.

The two backend correlation lines are preserved in backend-correlation.txt.
Original HEIC files remain unchanged on the owner's machine. Committed PNGs are
format conversions; any later redaction must be recorded in provenance.json.

## Follow-up found during review

The notification in IMG_4303 calls a Google OAuth app "Aura". If this notification
came from this PLUG sign-in, verify that the configured Google Cloud project's
OAuth branding is PLUG and its domain/contact details are correct. Do not alter
another unrelated app's OAuth project solely on the basis of this notification.
No credential or personal email is transcribed into this evidence record.

## Gate interpretation

Google/guest device acceptance and physical API correlation are recorded.
Google session persistence/logout are owner-reported; server-side revocation is
also covered by the separate automated checkpoint. These images do not establish
Apple sign-in, SMS receipt, a guest-to-new-member identity-preserving upgrade,
VoiceOver traversal, largest Dynamic Type, offline recovery, published legal
content or both engineers' simultaneous staging-profile checkpoint. G1 remains
open for those applicable requirements; no missing signature is fabricated.
