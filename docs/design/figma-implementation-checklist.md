# Figma implementation checklist

Person Two, P0.S7 (manual.docx §27.1): maps every screen and admin surface to
the phase that builds it and the gate that covers it. Nothing here is invented
— every row is a direct transcription of §13 (iOS), §14 (admin) and §15
(public web). Do not add a screen, route or component that isn't in one of
those three sections; that's a contract/manual change, not a checklist edit.

When a real Figma file exists, its frames should be named to match the
"Screen" column exactly, and this table should link each row to its frame.
Until then, this is the source of truth for what needs a frame at all.

## iOS — Person One builds, Person Two reviews copy/states/accessibility (§13.1)

| Screen group | Phase | Gate |
|---|---|---|
| Splash, sign in, permissions | P1 | G1 — session survives relaunch, logout revokes |
| Home prompt, query composer | P2 | G2 — structured extraction, at most one clarification |
| Searching, results, request detail | P2 | G2 — honest progress, validated offers only |
| Offer detail, reservation states | P3 | G3 — Confirmed only from a supplier event |
| Live Check, scout contribute, NOW answer | P4 | G4 — Unknown never becomes Confirmed silently |
| Activity, notifications, saved places | P4 | G4 — status labels consistent everywhere |
| Profile, settings, trust, help, report | P5 | G5 — deletion, revocation, report and block |

## Admin console — Person Two builds (§14.2)

Hard rules that apply to every row below, not just some of them: server-side
authorization on every route; no direct database access; every mutation
writes an immutable audit event (actor, reason, before, after, timestamp);
high-risk actions require a ≥20-character reason and step-up auth; Confirm
status is never set by hand; phone numbers/coordinates/tokens are masked
everywhere; every route is `noindex` and excluded from the sitemap.

| Surface | Phase | What it must do | Playwright must prove |
|---|---|---|---|
| Auth shell | P1 | Login, session, role display, forbidden page | Unauthenticated redirect; forbidden role sees a denial, not a blank screen |
| Supplier management | P3 | Onboarding, verification status, service area, consent record, suspension | Validation errors; consent visible; suspension requires reason; suspended supplier receives no outreach |
| Messaging monitor | P3 | Delivery status, inbound parse results, opt-out list, duplicate suppression | Numbers masked; STOP honoured; a duplicate webhook shows exactly one transition |
| NOW monitor | P4 | Live checks, observations, sources, freshness countdown, conflicts | Expired evidence changes its label in the UI; conflicting answers never render Confirmed |
| Request inspector | P5 | Search, list, detail, transition timeline, audited recovery | Reason field enforced; confirm action absent for the support role; every action writes an audit row |
| Moderation queue | P5 | Reports, blocks, restricted-intent log, evidence viewer, outcomes | Destructive actions confirm; audit appears after every mutation; evidence is access-controlled |
| Feature flags | P5 | Read-only for support, change-with-reason for admin | Support cannot toggle; an admin toggle writes an audit event and is reflected by the API |

Built today, ahead of its phase, as the Phase 0 protected shell: **Auth shell**
route protection exists (`web/src/proxy.ts` redirects unauthenticated requests
to `/admin/login`) — the real login screen and role display are still P1 work.

## Public website (§15.2) — Person Two builds

| Route | Title pattern | Indexed | Primary action |
|---|---|---|---|
| `/` | PLUG — find a barber who can take you now in `<city>` | Yes | Join the `<city>` beta |
| `/how-it-works` | How PLUG works — real replies, not listings | Yes | Join the `<city>` beta |
| `/for-barbers` | PLUG for barbers — get requests by text, free in beta | Yes | Opt in |
| `/privacy` | Privacy Policy — PLUG | Yes | None |
| `/terms` | Terms & Conditions — PLUG | Yes | None |
| `/support` | Support — PLUG | Yes | Contact support |
| `/404` | Page not found — PLUG | No | Back to home |
| `/admin/*` | — | No — noindex, excluded from sitemap | Server-authorised only |

`<city>` is Austin in every example in the manual (§2, launch wedge) — confirm
before shipping real copy rather than assuming.

Built today, ahead of its phase, as the Phase 0 public shell:
**`/`** exists with honest placeholder copy (no invented metrics, no CTA that
leads nowhere) — see `web/src/app/page.tsx`. `/privacy`, `/terms` and `/support` also
exist as placeholder shells (P1.S1). The other three public routes are not yet built; they don't have a phase number of their own in §15, so treat
them as due whenever `/` graduates from placeholder to real copy, not as a P0
requirement.

## Why no screens are P0

Phase 0 has no screen requirements — §27.1's task list is explicitly "the
public site and a protected admin shell. Do not build feature UI yet." Every
row above is P1 or later. This checklist exists now so nothing in §13–§15 gets
invented ad hoc when a phase starts; it is a map, not a to-do list to pull
forward.
