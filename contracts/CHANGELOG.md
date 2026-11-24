# Contract changelog

Every change to `/contracts` gets an entry. Both approvals required on the pull
request. Format:

```
### <version> — <date> — additive | BREAKING — <state token>
<what changed, in one or two sentences>
Fixtures updated: <paths>
Migration note: <none | what must happen, in what order>
Rollback: <what turning the flag off does>
```

### 0.7.3 — 2026-11-23 — clarification — P3.S13, P3.S14
Approval: the owner alone; frozen when the owner approves and merges the pull request. No
schema change: no new route, field, enum value or error code.

**Trust score v1 rules (owner decisions 2026-11-17, amended 2026-11-23), as the server computes
ProviderScoreBreakdown:**
- completion: completed jobs over confirmed jobs whose outcome is known. A job still in progress
  does not count; asker cancellations are excluded; a release or timeout before confirming is not
  a booking. Null below 3. PLUG records no provider cancel or no-show yet, so it is 100 whenever it
  has evidence.
- responsiveness: replies (an offer or a decline) by respond_by over replies plus silence; a reply
  after respond_by is silence; open matches are excluded. Null below 5.
- reliability: null until Phase 5 reviews; its basis is the confirmed jobs, as completion's.
- standing: 100 while active, 0 while suspended; basis is days since the profile was created or
  its standing last changed. Suspending also sets accepting false.
- value: weighted mean of the non-null components (completion 25, reliability 15, responsiveness
  10, standing 10); state new below 3 completed jobs.

Examples: new `p3-provider-profile-scored.json` (ProviderProfile with score_breakdown and
standing); `p3-admin-providers.json` corrected to these rules (reliability null, completion 100,
responsiveness null below 5 matches, value 94).
Fixtures: `admin.providers.list/success.json` (mirrors the example) and
`admin.providers.standing/suspended.json` (standing 0, responsiveness null) corrected; new
`providers.decline/suspended.json` and `providers.reservation/suspended.json` (403 forbidden).
Tests: `tests/contracts/fixture-manifest.json` is 0.7.3 with rows for the two new fixtures.
Migration note: none.
Rollback: none needed; documentation and fixtures only.

### 0.7.2 — 2026-11-17 — clarification — P3.S11
Approval: the owner alone (Person Two is not joining for now); frozen when the owner approves
and merges the pull request. No new route, field, enum value or error code; every response
added below is one the server already sends.

**Decided by the owner on 2026-11-17:**
- `Offer.expires_at` for a `portal` (in-app) offer is `available_at` plus 15 minutes. This
  resolves 0.7.1 open question 3 for portal offers and unblocks P3.S11. The same rule applies
  to `sms` offers too unless it is changed before P3.S5. Every portal offer in the fixtures and
  examples already followed it (available 20:20:00, expires 20:35:00), so none changed;
  `confirm_by` is unaffected (0.7.1 rule).

**Mechanical (from the P3.S6 and P3.S10 reviews, no new behaviour):**
- `POST /v1/me/devices` (`registerDevice`) lists 403 (no guest or member scope), 404 (the
  `provider_inbox` flag is off) and 413, as the server already answers.
- `POST /v1/requests/{request_id}/select` states the 403 `consent_required` rule and lists 415
  (follow-up item 13 from the P3.S6 review, PROJECT_STATE P3-contract-0.7.1).
- `InboxItem.service_name` is described as untrusted display text: clients render it as plain
  text, never markup.
- Corrects 0.7.1's rollback line, which did not name `POST /v1/me/devices`.

Fixtures: new `fixtures/me.devices/{validation-error,auth-error,unavailable}.json`,
`fixtures/requests.select/{consent-required,unsupported-media-type}.json`.
Tests (owner-authorized): `tests/contracts/fixture-manifest.json` is 0.7.2 with rows for the
five new fixtures; `fixtures.test.mjs` also requires every `fixtures/me.devices` file to be
registered; `validate.mjs` checks portal `expires_at` = `available_at` + 15 minutes on offer
lists, single offers and inbox items.
Migration note: none.
Rollback: `provider_inbox` off returns 404 on the inbox routes, on
`POST /v1/requests/{request_id}/select`, on `POST /v1/requests/{request_id}/offers` and on
`POST /v1/me/devices`. `sendProviderOffer` also lists 415 for a body that is not JSON.

**Open questions still awaiting the owner (from 0.7.1):** 1 (fan-out cap), 2 (reply window
against the t+300s stop), 3 for `sms` offers only (proposed above, confirm before P3.S5), 4
(SMS terms page and support contact), and the P3.S6 review items 11 (select replay code), 12
(`no_offers` against `not_confirmed` after a late release), 14 (`Reservation.offer_id`
required but the column is nullable) and 16 (`no_reservation` against `reservation_closed`
wording).

### 0.7.1 — 2026-11-17 — clarification, one webhook response change — P3.S6, draft
Follow-up to the 2026-11-14 contract-guard review of 0.7.0 (PROJECT_STATE next_actions
`P3-contract-0.7.1`). Approval: the owner is now the sole decision-maker. Person Two is not
joining for now, so items that needed both approvals are settled by the owner alone, and this
version is frozen when the owner approves and merges the pull request. 0.7.0 itself was
frozen when PR #46 merged (recorded in PR #50); its labels are corrected below. No new route,
field, enum value or error code. Each item is marked decided (owner), mechanical (no product
fact) or open (awaits the owner).

**Decided by the owner on 2026-11-16:**
- `InboxItem.respond_by` is `notified_at` plus 5 minutes, the outreach reply window (review
  item 3, in-app part). Fixtures and examples whose `respond_by` was 2 seconds short now match.
- `POST /v1/requests/{request_id}/select` is gated by the `provider_inbox` flag, like the inbox
  routes, although it also serves seed and sms offers; with the flag off it returns 404
  (item 10).

**Decided by the owner on 2026-11-17:**
- `Reservation.confirm_by` = min(`selected_at` + 20 minutes, max(`offer.available_at`,
  `selected_at` + 10 minutes)), where `selected_at` is the reservation's `created_at`. The
  provider always gets at least 10 and at most 20 minutes; for a later slot they must confirm
  before it starts. This replaces 0.7.0's "10 minutes after selection, or the offer's
  available_at if that is sooner", so `confirm_by` is never in the past at selection (open
  question 5 of the draft is resolved). Every fixture and example with a reservation now
  follows it: the sms offer (available 20:15:00, selected 20:00:09) has `confirm_by`
  20:15:00, and the portal offer (available 20:20:00, selected 20:02:30) has 20:20:00.
- The gaps the contract guard found, proposed in the draft, are now decided:
  - `MatchStatus`: a match whose reservation times out is `not_chosen`; one whose reservation the
    asker canceled is `closed`, and the inbox item still carries the canceled reservation.
  - A provider decision on a canceled reservation is 409 `reservation_closed`.
  - A reservation times out when the server clock reaches `confirm_by` (`ended_at` equals
    `confirm_by`, as in `p3-request-not-confirmed.json`); a decision at or after `confirm_by` is
    409 `reservation_closed` (0.7.0 said "after").
  - A `user_selected` request does not expire on its own `expires_at`; only `confirm_by` moves it
    (to `ranked`, or to `expired` with `not_confirmed`).

**Mechanical (no product fact):**
- `info.version` 0.7.1. "0.7.0, proposed" section labels in openapi.yaml, the `status` fields of
  templates.v1.json and grammar.v1.json, grammar.md, messages/README.md and fixtures/README.md
  now say frozen (item 8). Still saying "proposed", not edited here (other lanes):
  `backend/src/test/java/app/plug/foundation/ContractTest.java:50` and
  `FixtureContractTest.java:58` comments, and `tests/contracts/fixture-manifest.json`
  `"status"`.
- 409 on `POST /v1/admin/suppliers` now uses a new `SupplierConflict` response whose text names
  `supplier_exists` (field `phone`) and the idempotency codes, instead of `Conflict`'s identity
  wording (item 4). Body unchanged.
- Twilio webhook 403, 413 and 500 now carry the `Error` body (`forbidden`, `validation_failed`,
  `internal_error`), as the `Error` schema requires of every non-2xx (item 5). The only
  response-shape change; no webhook is built yet.
- templates.v1.json: "24h" in `optin_confirmed` and `help` is now a `{pause}` placeholder (max 3
  characters, example `24h`; the maximum is only for the length check and can be raised)
  (item 6). The `terms_url` and `support` rules now say their examples are not confirmed
  addresses (item 7; the examples are unchanged).
- Cancel's 200 description states that a selected offer's reservation comes back `canceled`
  with `ended_at` (already the 0.7.0 rule).

**Open questions, awaiting the owner (nothing chosen):**
1. Fan-out cap (item 1). `AdminMatchHistory.cap` is const 16, but `AdminMatch.wave` allows 3
   waves of 6+4+4 = 14, so 16 is unreachable; the manual says 14 (`SupplierMatcher`) and 16
   (`MatchService`). Options: (a) cap 14, matching the waves; (b) keep 16 and allow a fourth
   wave or larger waves; (c) make `cap` a server-set integer in a range instead of a const.
   Blocks P3.S15.
2. Reply window against the t+300s stop (item 2). A wave-3 contact at t+180s with a 5-minute
   window runs to t+480s. Options: (a) keep 5 minutes per contact and amend the manual's
   t+300s stop; (b) end every window at t+300s, so later waves get shorter windows (conflicts
   with the decided in-app `respond_by` unless that is limited to SMS); (c) start the waves
   sooner or shorten their spacing so every window ends by t+300s.
3. `Offer.expires_at` lifetime for `sms` and `portal` offers (item 3). Not decided; P3.S6 must
   not choose one. Blocks P3.S11.
4. SMS terms page and support contact (item 7). `plug.app/sms` and `support@plug.app` are not
   confirmed. The owner names the real page and contact (or a different form) before any opt-in
   text is sent (P3.S2).

Fixtures: `fixtures/requests.cancel/reservation-canceled.json` (new; a pending reservation
canceled); `respond_by` corrected in `providers.inbox/success.json`,
`providers.decline/{success,already-declined}.json` and
`providers.reservation/{confirmed,released}.json`. Examples: new
`p3-request-reservation-canceled.json`, `p3-inbox-item-timed-out.json` and
`p3-inbox-item-canceled.json` (the last two show the decided mappings), indexed in
`p3-index.json`; `respond_by` corrected in `p3-inbox.json` and `p3-inbox-item-confirmed.json`;
`confirm_by` (and the timed-out `ended_at` and `updated_at`) recomputed by the decided rule
in every reservation fixture and example.
Tests (done here with the owner's approval, Person Two's lane being unstaffed):
`tests/contracts/fixture-manifest.json` is 0.7.1 with a row for the new cancel fixture;
`validateInboxItem` allows a canceled reservation on a `closed` item and checks `confirm_by`
against the rule when the offer is present; `validateResource` checks that `confirm_by` is 10
to 20 minutes after selection and that a timeout ends at `confirm_by`;
`ios/PlugTests/RequestTests.swift` counts the new cancel fixture.
Migration note: corrects 0.7.0's note. V10 (expand only) starts with P3.S6, not P3.S2, and
contains only `request_reservations`, `request_matches.match_id`, `request_offers.withdrawn_at`
and the `not_confirmed` no-result reason. Supplier, SMS and suppression tables come with their
own steps.
Rollback: `provider_inbox` off returns 404 on the inbox routes and on
`POST /v1/requests/{request_id}/select`. `supplier_messaging` off as in 0.7.0.

### 0.7.0 — 2026-10-09 — additive, one client-visible relaxation — P3.S1, proposed
Proposed by Person One for the Phase 3 contract session (manual §27.4). Not frozen until both
approve the pull request; nothing in P3.S2 onward starts before then. Covers all eight items
§27.4 lists.

**Selection and reservation (§19.6):** `POST /v1/requests/{request_id}/select` moves a ranked
request to `user_selected` and adds `RequestResource.reservation` (`pending`, four-character
`booking_ref`, `confirm_by` 10 minutes or the slot, whichever is sooner). Only a provider event
confirms it: SMS `CONFIRM` or `POST /v1/providers/me/inbox/{match_id}/reservation`. New edge
`user_selected -> ranked` when the provider releases or `confirm_by` passes and other live
offers remain (alternate-offer recovery, P3.S7); otherwise `expired` with new
`NoResultReason` `not_confirmed`. `confirmed -> completed` is made by the server 3 hours after
the slot unless canceled. `poll_after_seconds` is now also present while
`await_supplier_confirmation`, so the app can see the confirmation arrive.
**Provider inbox and in-app offers:** `GET /v1/providers/me/inbox`, `POST
/v1/requests/{request_id}/offers` (a matched provider; the manual's route), decline (free,
recorded as a reply) and reservation confirm/release. `POST /v1/me/devices` registers an APNs
token; `ProviderMatchNotification` documents the payload (own sound and category). A match
over the provider's hourly cap is not made.
**Offer, shared by both channels:** `Offer.distance_m` (required) and `Offer.note` (in-app
only, 140 characters, no contact details) are added; `Offer.place` becomes optional and is
present exactly for `seed` and `sms` offers, because an individual provider's home is never
shown. This is the one change a strict client decoder sees; this pull request updates the iOS
`Offer` model (optional `place`, `distance_m`, `note`), `NoResultReason` (`not_confirmed`) and
the polling rule, and the backend now sends `distance_m` on Phase 2 offers.
**Trust score v1:** `ProviderProfile.score_breakdown` (completion, reliability,
responsiveness, standing; customer rating null until Phase 5) and `standing`. The asker still
sees only `ProviderScore`; New below three completed jobs is unchanged.
**SMS suppliers:** `POST /v1/suppliers/opt-in` (public, same 202 whatever the number's state;
consent is granted only by START from that phone), `Supplier` with consent state and trail,
verification status, service area, hours and a `plc_` place (one place model with Phase 4).
**Twilio:** `POST /v1/webhooks/twilio/inbound` and `/status` under a `twilioSignature` scheme,
outside the session filter; signature over the configured public URL, MessageSid claimed for
7 days, empty TwiML response.
**Messages:** `contracts/messages/` now holds `templates.v1.json` (17 SMS texts and the push
alert, each fitting two GSM-7 segments at maximum length), `grammar.md` and `grammar.v1.json`
(YES/NO/CONFIRM/RELEASE/STOP/START/PAUSE/HELP, deterministic, one open context per supplier)
and `cases.v1.json` (76 regression cases the P3.S5 parser must pass). Wording is Person
Two's; this is a draft for her to rewrite. SMS consent version `sms-2026-10-09`.
**Admin (owner-only writes, every read audited, numbers masked to the last two digits):**
suppliers list/create/get/update/verification, `GET /v1/admin/messages` (the messaging
monitor; no bodies), `/v1/admin/opt-outs`, `/v1/admin/requests/{request_id}/matches`,
`/v1/admin/providers` and provider standing.

Proposed defaults to agree at the session (each is one constant to change):
fan-out 6 then 4 then 4, combined cap 16 across SMS and in-app (as built in Phase 2; the
manual's `SupplierMatcher` sketch says 14, `MatchService` says 16); outreach reply window 5
minutes; reservation confirmation 10 minutes; provider notifications 4 per hour; pause 24
hours; offers above the asker's budget refused rather than shown; one hint reply per
conversation; auto-complete 3 hours after the slot; trust score v1 reweights the four
existing components to 60 points; supplier writes are owner-only (ADR-013 keeps staff
read-only).

Fixtures: 120 new files under `fixtures/requests.{select,send-offer}`, `providers.{inbox,
decline,reservation}`, `suppliers.opt-in`, `admin.{suppliers.*,messages,opt-outs,matches,
providers.*}`, plus `requests.get/{reservation-pending,confirmed,reservation-released,
not-confirmed}` and `requests.offers/sms-and-app`; existing offer fixtures gain `distance_m`.
28 examples `contracts/examples/p3-*.json`, indexed by `p3-index.json` and checked by
`ContractTest`. `tests/contracts/messages.test.mjs` checks copy, grammar and cases together;
`fixtures.test.mjs` now covers `/v1/suppliers` and checks reservation, place, note,
inbox and masked-number rules, with mutation tests. Manifest at 0.7.0.
Migration note: V10 (expand only) when P3.S2 starts: suppliers, consent events, places for
suppliers, sms messages, suppression, reservations, devices, provider standing and scores.
Rollback: Phase 3 routes sit behind a `supplier_messaging` flag (SMS) and `provider_inbox`
(in-app); off, the routes return 404 and no message leaves PLUG. `Offer.place` stays present
on every offer while no `portal` offer exists.

### 0.6.1 — 2026-10-07 — clarification — proposed
Approved by Person One (project owner) on 2026-10-07; Person Two approves the pull request.
No shape changes. `Category`: a request is created in the asker's own words only when the model
read the ask as a lawful service and named it; without a model reading the ask the person gets
the one question (Person Two's 2026-10-06 rerun showed the rules alone turning reworded harmful
asks into requests). A name that matches a listed skill becomes that skill, licence rule
included, and matching uses the request's name as well as the ask's words.
Fixtures: `fixtures/staff.{login,verify,accept}/` (the three staff sign-in routes, raised by
Person Two), and `tests/contracts/fixtures.test.mjs` now requires coverage under `/v1/staff`
too; responses without a body (204) need no fixture. Manifest at 0.6.1.
Migration note: none.
Rollback: none needed; the behaviour change is in the intent adapter.

### 0.6.0 — 2026-10-05 — additive — proposed
Approved by Person One (project owner) on 2026-10-05; Person Two approves the pull request.
**Staff accounts (ADR-013):** `POST /v1/staff/login`, `POST /v1/staff/login/verify`,
`POST /v1/staff/invites/accept`, `GET /v1/admin/staff`, `POST /v1/admin/staff/invites` and
`POST /v1/admin/staff/{user_id}/disable`; `Account.type` gains `staff` (admin scope only). Staff
are invited by email, sign in with email, password and an emailed six-digit code, and only that
session carries the second factor `/v1/admin` requires. `Consent.accepted_version` is now always
written (null for staff), as the schema already required.
**Asks in the person's own words (ADR-011 amendment):** a clear service ask naming no listed
skill and no provider's own words now creates a request whose `category` is a `custom_` tag
and whose `service_name` is the service in the asker's words, instead of the category
question. No shape changes.
Fixtures: `fixtures/admin.staff.{list,invite,disable}/`; manifest at 0.6.0.
Migration note: V9 (expand only: `staff` account type, `staff_accounts`, `staff_invites`,
`staff_login_challenges`).
Rollback: `PLUG_STAFF_MAIL_DELIVERY=none` refuses every staff sign-in (503); disabling staff
accounts revokes their sessions. Own-words requests stop if the adapter change is reverted;
existing custom requests keep their labels.

### 0.5.0 — 2026-10-05 — approval — frozen on merge
Approved by Person One (project owner) on 2026-10-05 for everything listed under 0.5.0 and its
amendments, including `contracts/skills.yaml`. Person Two's approval of the pull request that
carries this entry completes the §7.1 two-approval rule; when it merges, every Phase 2 request,
ask, provider and admin route is frozen@0.5.0. Further changes need a new version.

### 0.5.0 amendment — 2026-10-05 — additive — staff inspection routes (P2-TWO.S12)
`GET /v1/admin/skills` (vocabulary with provider counts, plus providers' own skills),
`GET /v1/admin/skills/gaps`, `GET /v1/admin/classifications` and `GET /v1/admin/refusals`, with
`AdminCursor`/`AdminLimit` keyset paging (1–100, default 50; a bad cursor or limit is 400).
Admin scope plus a completed second factor, as for all of `/v1/admin`; responses are
`Cache-Control: no-store` and every read writes an `admin.read` audit event. They return no ask
text, coordinates or identities; a refusal is only its rule and time. No staff identity is
issued yet, so in this phase every caller is refused (401/403) until the staff sign-in path is
designed.
Fixtures: `fixtures/admin.{skills,gaps,classifications,refusals}/`.
Migration note: none (reads existing tables).
Rollback: `requests_v2` off removes the routes.

### 0.5.0 amendment — 2026-10-03 — additive — proposed — direct skill entry
Owner request: entering a listed name in `custom_skills` now resolves it to its canonical
skill instead of returning `listed_skill`. Licence checks still apply, and unlisted labels
retain own-words matching. Suggestions are optional in the app.
Fixtures updated: none (response shapes unchanged); covered by `AskProviderTest`.
Migration note: deploy the backend before the direct-entry app; no database migration.
Rollback: restore the previous app and backend together.

### 0.5.0 amendment — 2026-10-02 — additive — proposed — larger vocabulary and own-words skills (ADR-011)
Owner decision. `contracts/skills.yaml` grows from 35 to 115 tags (new licensed tags: hvac,
plumbing_major, roofing, pest_control, tattoo, piercing, facials, driving_lessons).
`ProviderSetup.custom_skills` (≤5 labels, 3–40 characters; omit to keep, `[]` to remove) and
`ProviderProfile.custom_skills` hold skills in the provider's own words; `skill_tags` may be
empty when `custom_skills` is not (otherwise 400 `required`). A label naming a listed skill is
400 `listed_skill`, one with no specific word 400 `too_vague`, an unsafe one 422
`restricted_intent`. `Category` may be `custom_<keywords>` on a request the server matched to
own-words skills by keywords; clients display `service_name`. The proposal example now uses
"chimney sweeping" as the unlisted term, since "crochet locs" is a listed synonym of `locs`.
`POST /v1/providers/skills` now documents its 413 (body over 96 KiB) and 422 (unsafe
own-words label) responses, which the server already returned.
Fixtures updated: `fixtures/providers.propose/success.json`; added
`fixtures/providers.skills/{restricted-intent,payload-too-large,listed-skill}.json`.
Migration note: `V8__expanded_and_custom_skills.sql` inserts the 80 new tags and adds
`provider_custom_skills` (keywords GIN-indexed). Custom tags register in `skill_vocabulary`
under parent `custom`; the startup check ignores those rows. Expand-only.
Rollback: `requests_v2` off removes the routes; the rows are inert without them.

### 0.5.0 amendment — 2026-10-02 — additive — proposed — optional business profiles
Owner-authorized (implemented with Codex, completed by Person One). A provider may add
optional public details: `BusinessProfile` (`name` ≤80, `about` ≤300, `photo_base64` a JPEG
of at most 48 KiB decoded and 512×512, re-encoded server-side so EXIF/GPS is dropped, and
up to five `BusinessLink`s of `label` plus a public `https://` URL with no credentials,
no IP or `.local` host). `ProviderSetup.business`: omitted keeps the stored details, `{}`
removes them. `ProviderProfile.business` and `ServiceOffer.business` return them; an offer
carries them only through an explicit `provider_id`, never by matching a name or place.
Nothing is fetched server-side and links open only on a customer tap. `POST
/v1/providers/skills` accepts up to 96 KiB for the thumbnail; every other route keeps 16 KiB.
`ServiceOffer.provider_score` now reflects the provider's real completed jobs and trust.
Fixtures updated: `fixtures/requests.offers/business-profile.json`, `fixtures/asks.get/answered.json`
(answered place question with source initials); manifest regenerated.
Migration note: `V7__optional_business_profiles.sql` adds `provider_profiles.business`
(JSONB, default `{}`, ≤75 000 bytes) and nullable `request_offers.provider_id`. Expand-only.
Rollback: `requests_v2` off removes the routes; the columns are inert without them.

### 0.5.0 — 2026-10-02 — BREAKING vs proposed 0.4.0 (unmerged) — proposed — manual v4 / ADR-010
Manual v4 Part V (P2.S10–P2.S17). One ask field serves two kinds of ask: `POST /v1/asks`
classifies into `service_request` or `place_question` and returns `AskResult` (exactly one of
`request`, `place_question`, or a single `clarification` with `field: ask`), with
`GET /v1/asks/{ask_id}` and `POST /v1/asks/{ask_id}/clarifications`. Skills come only from
the new controlled vocabulary `contracts/skills.yaml` (35 tags, owned by Person Two, changed
by pull request plus migration): `RequestConstraints.search_terms` is removed and replaced by
required `skill_tags` (vocabulary tags) and `licence_required`. Any lawful service is in
scope; the restricted-intent policy is now the only refusal path and runs before any model
call (refusals are audited; place questions about a private place are refused the same way).
Provider capability is added to the caller's existing account: `POST
/v1/providers/skills/propose`, `POST /v1/providers/skills`, `GET /v1/providers/me` (404 until
the caller offers a service); a `requires_licence` tag needs `licence_ref`
(`details[].code` `licence_required`) and an invented tag is refused (`unknown_skill`).
`ServiceOffer` gains required `provider_score` (`new` below three completed jobs, never 0).
`TruthLabel` gains `not_verified`, reserved for `WebAnswer`, which can never carry a human
label. The Apple Maps listing from ADR-009 is withdrawn. `POST /v1/asks` shares the creation
rate budget with `POST /v1/requests`. Error codes and auth@0.2.2 are unchanged.
Fixtures updated: new `fixtures/asks.create|asks.get|asks.clarify|providers.propose|
providers.skills|providers.me` (captured from the real backend, errors from templates);
every `fixtures/requests.*` resource and `contracts/examples/requests-*` migrated from
`search_terms` to `skill_tags`/`licence_required`/`provider_score`; `fixtures/intents/p2.jsonl`
46 vectors re-labelled against the vocabulary; manifest at 117 rows.
Migration note: `V6__asks_skills_providers.sql` adds `skill_vocabulary` (seeded from
skills.yaml; the backend refuses to start if the two disagree), `asks`, `place_questions`,
`provider_profiles`, `provider_skills`, `provider_availability`, `provider_scores`,
`request_matches` and `vocabulary_gaps`. Expand-only. Backend first, then the iOS build.
Rollback: `requests_v2` off removes every route above; the Phase 0 stub stays.

### 0.4.0 — 2026-10-01 — BREAKING vs proposed 0.3.0 (unmerged) — ADR-009
Owner decision: PLUG serves any lawful service, not only barber and beauty. `Category`
becomes a snake_case identifier (`^[a-z][a-z0-9_]{1,39}$`) instead of the enum
`[barber, beauty]`; `RequestConstraints` gains required `service_name` (null exactly when
category is null) and `search_terms` (0–5 phrases, empty exactly when category is null);
`CreateRequestBody` gains optional `time_zone` (IANA) so "tomorrow" is the person's day;
budget limits widen to 500–500000 cents ($5–$5,000). The `unsupported_category` refusal
is removed: a service no participating supplier covers is created and ends `expired` /
`no_coverage`, and the iOS app may list real nearby businesses from Apple Maps with price
and availability shown as Unknown. Clarification options are chosen per request. Error
codes, routes, status/next_action enums and auth@0.2.2 are unchanged.
Fixtures updated: every `fixtures/requests.*` resource and `contracts/examples/requests-*`
gains `service_name`/`search_terms`; `requests.create/unsupported-category.json` and
`requests-unsupported-category-error.json` removed; `requests-create-open-service.json`
added; `fixtures/intents/p2.jsonl` now 46 vectors (open services, $1,200, over-cap).
Migration note: `V5__open_service_scope.sql` is expand-only (relaxed checks, new nullable
columns, backfill of V4 barber/beauty rows). Backend first, then the iOS build.
Rollback: `requests_v2` off; V5 leaves V4 data valid.

### 0.3.0 — 2026-10-01 — BREAKING (POST /v1/requests only) — P2.S1
Proposes the Phase 2 request contract (manual.docx §18.3, §19.5, §19.6, §27.3).
Still awaiting both engineers' approval and merge; it is not frozen or implemented.
Person Two hardening: an unanswered draft keeps its null category when canceled or
expired with clarification_unanswered, rather than inventing a category to close it.
Restricted errors omit a created resource ID but retain error.request_id for correlation.
Fixtures now cover every documented HTTP response across all five operations, plus
draft cancellation/expiry, ownership denial, and the labelled intent cases. See
`tests/contracts/fixture-manifest.json` and `fixtures/intents/p2.jsonl`.
`POST /v1/requests` is replaced: body `CreateRequestBody` (`text` ≤ 500 plus optional
`category`, `budget_cents`/`currency`, `needed_by`, `max_distance_m`, and `location`
with `precision`), required `Idempotency-Key` (16–128), `plugSession` auth instead of
`stagingJwt`, 201 `RequestResource` instead of 202, and new 409 / 422 responses. Adds
`GET /v1/requests/{request_id}`, `POST /v1/requests/{request_id}/clarifications`,
`GET /v1/requests/{request_id}/offers` and `POST /v1/requests/{request_id}/cancel`.
Adds the `RequestStatus` (11 values, §19.6 transitions plus `draft -> expired`) and
`NextAction` (7 values) enums with a one-to-one status mapping, `RequestProgress`,
`Clarification` (category only, at most one per request), `NoResultReason`, `Offer`,
`Place`, `TruthLabel` and `OfferSource`. Money is integer cents plus ISO 4217 (USD only
in V1); time is ISO-8601 with an explicit offset, emitted in UTC. The error-code enum
is unchanged: new outcomes are `details[].code` tokens — `unsupported_category`,
`in_the_past`, `too_far_ahead`, `not_an_option`, `consent_required`,
`idempotency_key_reused`, `request_in_progress`, `not_awaiting_clarification`,
`not_cancelable`. All identity routes (auth@0.2.2) are unchanged.
The Phase 0 stub schemas are renamed `Phase0RequestCreate`, `Phase0Location` and
`Phase0RequestResponse`, marked deprecated, and kept only so the stub the backend still
serves stays tested; they are removed in the implementation pull request.
Examples: `contracts/examples/requests-*.json` — one per documented outcome.
Fixtures: `fixtures/requests.{create,get,clarify,offers,cancel}/` now use the proposed
0.3.0 shapes (§7.2). The old stub remains covered by `request-response.json` and the
explicit Phase 0 Bruno requests until backend implementation. `FixtureContractTest`
validates the new response bodies; `pnpm test:contracts` additionally checks status
coverage, cross-field invariants and the labelled dataset's input schema expectations.
Tests: `ContractTest` validates every new example and checks the status → next_action
mapping, the present-if-and-only-if fields and the progress invariants across them.
Migration note: no database change in this pull request. The backend ships the new routes
behind flag `requests_v2` (default off) with the P2.S3/S4 migrations; iOS adopts them in
P2.S9. Neither app calls `POST /v1/requests` today. The only consumers are the two
Bruno requests in `tests/api/requests-create-*.bru`, which target the stub and are
rewritten in Person Two's P2.S2.
Rollback: revert this pull request; nothing depends on it until `requests_v2` exists.
With the flag off, the Phase 0 stub keeps its 0.1.0 behaviour.

### 0.2.2 — 2026-09-28 — metadata reconciliation — approved implementation
Align OpenAPI info.version with the existing 0.2.2 signup/signin-intent entry.
No endpoint, schema, runtime behavior or fixture content changes. The implementation
and fixtures were approved through PRs #25/#27 and reached main through #28.
Person One authorized the completion record on 2026-09-28. This contract record
is not the separate G1 device/staging sign-off.
Migration note: none. Rollback: metadata-only revert.

### Unreleased — 2026-09-26 — fixtures and examples only — P1.S1
No route or schema change. Replaces the unimplemented 0.2.0 draft shapes (guest
`device_id`, nested terms/privacy consent, flat session fields, `chl_` challenges,
relative expiry, JWT access tokens and the auth `Idempotency-Key` replay promise) with
examples and fixtures that match the implemented contract: opaque tokens, 201 on
sign-in, `consent_version`, `cha_` challenges, absolute expiry, the 30-day verified /
7-day guest refresh policy (ADR-006), Google sign-in, `sign_up`/`sign_in` intent with
`account_exists`/`account_not_found`, and `503 dependency_unavailable` when phone
delivery or Google is not configured. Only `POST /v1/requests` accepts
`Idempotency-Key`; auth routes do not replay, and `FixtureContractTest` keeps it so.
Validation `details[].field` now uses the snake_case wire name (`phone_number`, not
`phoneNumber`), matching the request body and the fields `ApiException` already used.
Fixtures updated: `fixtures/auth.{apple,google,guest,phone.start,phone.verify,refresh,logout}/*`,
`fixtures/me.{get,consent,sessions}/*`; removed `fixtures/requests.create/guest-restricted.json`
(guests are not restricted on that route).
Tests: `FixtureContractTest` validates every fixture and example against its schema;
`FixtureBehaviourTest` and `UnavailableProviderTest` send the examples to the real
backend and compare status, code, details and message with the fixture.
Migration note: none. Rollback: revert the commit; no server state depends on it.

### 0.2.2 — 2026-09-25 — additive — draft, not jointly frozen
Apple/Google authentication and phone verification accept optional `intent`:
`sign_up` rejects an existing verified identity; `sign_in` rejects an unknown one.
Both return HTTP 409 with `error.code=conflict` and an `intent` detail containing
`account_exists` or `account_not_found`. Checks run after ownership verification.
Omitting intent preserves the earlier combined flow. Identity matching uses the
provider's verified subject, not an unverified or cross-provider email address.
Fixtures/tests: GoogleSignInTest, AuthenticationModelTests.
Migration note: no database migration; deploy backend before the updated client.
Rollback: revert clients first; earlier servers reject the new request field.

### 0.2.1 — 2026-09-24 — draft, not jointly frozen
User-requested expansion: Google sign-in (`POST /v1/auth/google`) and the `google`
account type; real SMS through explicitly configured Twilio delivery. Google checks
signature, issuer, server client audience, expiry, nonce and single use. Existing
phone verification creates or returns an account after OTP verification, without
revealing whether a number is registered. No passwords are stored; recovery is
specific to the chosen provider.
Fixtures/tests: GoogleSignInTest and TwilioPhoneCodeSenderTest.
Migration: apply V3 before enabling Google. Ship clients accepting the new account type
before enabling the provider. No changes to already-applied migrations.
Rollback: clear Google client configuration and select `phone-delivery=none`;
existing Google sessions remain readable. Keep V3 applied.

### 0.2.0 — unreleased — P1.S1
Additive. Adds the identity and consent surface: `POST /v1/auth/apple`,
`POST /v1/auth/phone/start`, `POST /v1/auth/phone/verify`, `POST /v1/auth/guest`,
`POST /v1/auth/refresh`, `POST /v1/auth/logout`, `GET /v1/me`,
`POST /v1/me/consent`, `GET /v1/me/sessions` and
`GET`/`DELETE /v1/me/sessions/{session_id}`; the `plugSession` bearer scheme; and the
`Conflict`, `NotFound` and `DependencyUnavailable` responses. The error-code enum is
unchanged — a wrong or expired one-time code is a `validation_failed` whose
`details[0].code` is `invalid` or `expired`, and a spent attempt budget is `rate_limited`.
Access tokens live 15 minutes. Refresh tokens rotate on every use and live 30 days for a
verified account, 7 days for a guest; replaying a rotated token revokes the whole chain.
No Phase 0 operation changed.
Fixtures: `contracts/examples/{session,phone-challenge,me,invalid-code-error,account-link-conflict-error}.json`
Migration note: `V2__identity.sql` creates `users`, `identities`, `sessions`,
`consents`, `phone_challenges`, `apple_token_uses` and `audit_events`. It runs before
the code that reads them, and it adds no column to an existing table.
Rollback: set `plug.identity.enabled=false`. The auth routes stop being registered and
Phase 0 behaviour is unchanged; no migration has to be reversed.

### 0.1.0 — unreleased — P0
Initial contract: `GET /health`, `GET /health/ready`, `POST /v1/requests` stub,
and the shared error envelope.
Fixtures: `fixtures/requests.create/{success,validation-error}.json`
Migration note: none.
