# ADR-009: Any lawful service, Claude extraction, nearby-business discovery

- Status: Accepted by the project owner on 2026-10-01. **Superseded in part by
  [ADR-010](ADR-010-manual-v4-asks-skills-providers.md) on 2026-10-02:** free-form
  categories and `search_terms` are replaced by the controlled skill vocabulary, and the
  Apple Maps nearby-business listing (point 3) is withdrawn. Points 2 (Claude extracts,
  output untrusted, rules fallback) and 4 (budgets and time) still stand.
- Scope: amends manual.docx §1.3 rule 5, §2.1 (Launch: "one category"; Truth), §19.5,
  §25.6 (category allow-list) and §27.3 for Phase 2 onward

## Decision

PLUG is no longer limited to barbers and beauty. A person asks for anything a human can
look for — "I need to repair my shoe for $45 tomorrow, who is available?" — and PLUG
extracts the service, budget, time and place and answers with results that match.

1. **Open service scope.** `category` becomes a free-form service identifier
   (`shoe_repair`, `plumber`, `barber`, …) with a human-readable `service_name` and up to
   five `search_terms`. Unsupported-category refusal is removed. The restricted-intent
   policy (illegal goods and services, stalking, private-person tracking, fraud,
   weapons, cyber abuse) still refuses with 422, creates nothing and writes an audit event.
2. **Claude extracts structure.** The intent adapter calls the Claude API (official Java
   SDK, model `claude-opus-5-5` by default, low effort, strict JSON schema, 6-second
   deadline). Its output is untrusted input: schema- and range-checked before use, never
   allowed to set status, offers, prices or truth labels. Explicit client fields win; then
   unambiguous rule-based parses (dollar amounts, relative times); then Claude. A timeout,
   provider error, refusal or invalid output falls back to the built-in rules, never a 500.
   The key lives only in the backend environment (`ANTHROPIC_API_KEY`), never in a client.
3. **Results.** Participating suppliers (seed data now, opted-in suppliers in Phase 3)
   produce validated offers exactly as before. When none cover the service, the request
   ends `no_coverage` and the iOS app searches Apple Maps on the device for real nearby
   businesses using the server's `search_terms`. Those are listings, not offers: price and
   availability are shown as **Unknown**, nothing is booked, and nobody is contacted.
4. **Budgets** widen to $5–$5,000 so ordinary services fit; **time** understands
   "tomorrow"/"tonight" in the person's own time zone (`time_zone`, IANA, sent by the app).
5. **Design.** The Ask experience moves to a bold, warm look — large prompt, service
   suggestions, card results with clear price/time/distance — inside the manual's §16 bans
   (no gradients, no glass, no fake proof).

## Consequences

- Contract 0.4.0 supersedes the unmerged 0.3.0 category model (see `contracts/CHANGELOG.md`).
  Both engineers must still approve it before merge; this ADR does not imply that approval.
- Each extraction is a paid Claude call. Without a key the app still works on the rules.
- Apple Maps discovery depends on device location or a typed address, and on Apple's data.
- Phase 3 outreach must still be bounded and opt-in; open scope does not authorize texting
  businesses that have not consented (§2.1 Supplier contact is unchanged).
- The labelled dataset, fixtures, Bruno, live suite and UI tests drop unsupported-category
  expectations and cover open services instead.
