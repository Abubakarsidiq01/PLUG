# ADR-014: Which skills require a licence during the private test

- Status: Accepted for the private test by Person One (project owner) on 2026-10-07, answering
  Person Two's four vocabulary questions (`docs/testing/phase2-person-two-review-2026-10-05.md`
  §3). Revisit before any public launch (Phase 5), with advice on the states PLUG opens in.
- Relates to: `contracts/skills.yaml` (`requires_licence`), ADR-011.

## What `requires_licence` does today

A provider offering a skill with `requires_licence: true` must give a licence reference, and
only such providers are matched to it. PLUG does not verify the reference; it records it and
the offer says the provider is new and unverified. So the flag is a gate on who can offer, not
a check that anyone is licensed.

## Decisions

1. **Hair and beauty** (`barber`, `braids`, `hair_styling`, `hair_coloring`, `nails`,
   `lashes`, `waxing`): no licence flag during the private test. Many states license these
   trades, but a reference PLUG cannot check would turn away most informal providers in the
   test zone without making anyone safer. `facials`, `massage`, `tattoo` and `piercing` keep
   theirs: they break the skin or carry clear health risk.
2. **Food and drink** (`catering`, `personal_chef`, `baking`, `bartending`): no licence flag
   during the private test, for the same reason. Before public launch, food handling and
   alcohol service need a decision per state, most likely a flag on `bartending` and
   `catering`.
3. **Brakes under `auto_repair`**: deliberate. Mechanics are generally not licensed
   individually in the US, and removing the synonym would only make brake asks miss the
   right providers. Safety-critical vehicle work is a launch-review item, not a test-zone flag.
4. **Nested phrases**: the longest phrase wins. That behaviour is now guarded in the backend's
   own build: `AsksDatasetTest` runs every `overlap-` row of the dataset ("henna tattoo" is
   `henna`, not the licensed `tattoo`) on every change, so a rule change cannot silently
   break it.

## Consequences

- The private test stays open to the informal providers it is meant to reach.
- Every entry here is listed for the Phase 5 launch review, where it must be decided per state.
