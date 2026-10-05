# ADR-010: Manual v4 — two kinds of ask, a controlled skill vocabulary, providers on the same account

- Status: Proposed by Person One on 2026-10-02 at the project owner's direction ("use the new
  production manual to design Phase 2 entirely"). Implemented behind `requests_v2`. Needs
  Person Two's review and approval with contract 0.5.0; not jointly approved yet.
- Scope: manual v4 Part V, P2.S10 to P2.S19 (Person One) and the artefacts Person Two owns
  (P2.S7 dataset, P2.S8 `contracts/skills.yaml`, P2.S9 Bruno), which Person One drafted so
  neither lane waits. Supersedes ADR-009 points 1 and 3.

## Decision

1. **One field, two kinds of ask.** `POST /v1/asks` accepts any text. The server classifies it
   as a `service_request` (a person to do something) or a `place_question` (what is happening
   at a public place now). An ask the server cannot classify gets exactly one clarifying
   question; the server never guesses a pipeline.
2. **Skills come from a controlled vocabulary.** `contracts/skills.yaml` lists 35 tags with
   synonyms and display names. Claude, or the built-in rules when no key is set, maps words
   onto those tags and never creates one. Unmatched terms are shown to the person and stored
   in `vocabulary_gaps` for review; nobody is matched on them. The `skill_vocabulary` table
   is seeded by migration, and the backend refuses to start if it disagrees with the file.
   Childcare, elder care, medical, legal and financial advice are deliberately absent.
3. **Restricted intent is the only refusal.** The category allow-list is gone. The policy runs
   before any model call, refuses with 422 `restricted_intent`, creates nothing, contacts
   nobody, and writes an audit event naming the rule. Place questions must be about a public
   place; a private home or a named person's location is refused the same way.
4. **Providers are a capability, not a second account.** Any account can add skills, a travel
   radius, a base location and weekly availability with `POST /v1/providers/skills`. A
   `requires_licence` skill needs a licence reference before it can be matched. The Inbox
   tab appears only once the account has a provider profile.
5. **Matching** is skill overlap, inside the provider's own radius, inside their availability
   window, with a licence where required, never the asker themselves. Candidates are ranked
   by the manual's §19A score, weighted response rate 60%, trust 30%, proximity 10%, so a
   responsive newcomer outranks a quiet high scorer; fanout 6, hard cap 16. A provider with
   fewer than three completed jobs is `new`, never shown as a score of 0.
6. **Web answers are never promoted.** A `WebAnswer` is always `not_verified` and is drawn
   dashed. No configuration or later code path can give it a human truth label.
7. **Design is manual v4 §10.** Ink on paper, no brand colour, no shadows, radii 7/9/12/20,
   the system face on iOS. The Apple Maps listing and the "bold and warm" Ask screen from
   ADR-009 are withdrawn.

## Consequences

- Contract 0.5.0 replaces the unmerged 0.4.0; both engineers approve it in one §7.1 session.
- P0 and P1 are frozen (`completed_phases`). The design-token rename keeps their code
  compiling through `design/token-aliases.json` instead of editing it.
- The website is Person Two's lane (§6.6). A partial v4 retheme draft is handed over as
  `docs/handoff/web-v4-retheme-draft.patch`, not committed to `/web`.
- Place questions return real counts and Unknown until people nearby can answer (Phase 4).
