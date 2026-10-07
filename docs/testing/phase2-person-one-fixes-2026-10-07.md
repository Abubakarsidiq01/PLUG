# Phase 2: Person One's fixes after Person Two's review (2026-10-07)

Answers `phase2-person-two-review-2026-10-05.md` and `phase2-person-two-rerun-2026-10-06.md`
item by item. Built on Person Two's branch (pull request #37), contract 0.6.1. Not a G2
signature.

## 1. Restricted asks (rerun §2.1, the G2 blocker)

Fixed in four layers (ADR-011, 2026-10-07 amendment):

1. The policy refuses the same intents in other words (violence against a person, drugs
   without a prescription, forged documents described, tailing or checking on a particular
   person, "without her knowing", hidden cameras, diagnosis, childcare, therapy).
2. Claude's schema gains `restricted`; a flagged ask is refused and audited as
   `restricted_intent:model_flagged`.
3. A request in the asker's own words is created only from Claude's label, after the policy
   checks the label. With the rules alone the person gets the one question.
4. Ordinary asks that share words with the new rules are tested to stay accepted
   ("Photographer to shoot my daughter's graduation", "Diagnose my car's check engine
   light", "Psychology tutor for my exam", "Make me a passport photo", and twelve more).

## 2. Listed skills and licences (rerun §2.2)

- A label that names a listed skill becomes that skill, so its licence rule applies
  (`OwnWordsWithModelTest`: "Brighten up my kitchen ceiling" labelled "install track
  lighting" is `electrical`, `licence_required` true).
- The suggested synonyms are in `contracts/skills.yaml`; the matcher now reads "clean my mom's
  house" and "mount a 55 inch TV". Claude is told that a described problem names its trade,
  and that anything with a motor is `motorcycle_repair`.
- Matching an own-words request uses its name as well as the ask, and the keyword stemmer no
  longer leaves "restring" and "restringing" different.

## 3. Place questions (review §2.3)

"Is the DMV busy?" records "DMV", "Is the DMV line long this morning?" and "Are there any
tables free at the student union?" are place questions, and "How busy is the campus gym"
records "campus gym".

## 4. The labelled dataset

| Run | Agree | Restricted refused |
|---|---|---|
| Person Two, 2026-10-06, contract 0.6.0, rules | 61 / 91 | 16 / 31 |
| Backend test `AsksDatasetTest`, rules | 91 / 91 | 31 / 31 |
| Live, rules only (`asks-live-rules-2026-10-07.json`) | 91 / 91 | 31 / 31 |
| Live, Claude Sonnet 5.5 (`asks-live-claude-2026-10-07.json`) | 91 / 91 | 31 / 31 |

The first Claude run disagreed on one row, `overlap-ebike-repair` ("E-bike repair, the motor
cuts out" read as `bike_repair`); after the instruction above it reads `motorcycle_repair`
three times out of three, and the report is from the rerun. The labels were reviewed and
kept as written.

## 5. Vocabulary questions (review §3)

Answered in ADR-014: no licence flag on hair, beauty, food and drink during the private test,
"brakes" stays under `auto_repair`, and nested phrases are guarded by `AsksDatasetTest`.
Each is listed for the launch review.

## 6. Staff console (rerun §5, §6)

- Fixtures for `/v1/staff/login`, `/v1/staff/login/verify` and `/v1/staff/invites/accept`,
  and `fixtures.test.mjs` now requires them.
- Sign-in limits count each person: the backend believes `X-Forwarded-For` only from
  `PLUG_TRUSTED_PROXIES`, and the console passes on its caller's address.
- `/admin/staff`: the list, invitations and disabling for owners, with Playwright and axe at
  360, 768 and 1280 px.
- The invitation token leaves the address bar once read; a request marked HTTPS by a proxy
  always gets Secure cookies.

Still as recorded: two tabs refreshing at once can end the session (the person signs in
again), and the console needs switching on in an environment.

## 7. iOS (review §5, rerun §4)

| Finding | Change |
|---|---|
| Notification banners with names in five device captures | Banner band covered in the five and their greyscale copies; recapture with Do Not Disturb |
| Identical screenshot pairs | A second view is kept only when the screen changed; Unknown without a web answer is its own state |
| Words cut or broken at largest text | Icon-and-text rows stack at accessibility sizes; placeholders wrap |
| "Answere/d" at default size | Counters fall back to a column when a label would break |
| Sheet title under Cancel | The sheet's name is in its navigation bar |
| Disabled "Add skill" and Ask placeholder contrast | Disabled actions are ink on a quiet fill; placeholders use the body grey |
| More than one ink control | "View details" is outlined; selected filters and chips are outlined with a check |
| "Meet your options" headline | The headline is the result: "3 offers" |
| Shadows on back and refresh | System navigation controls; unchanged |
| Lowercase "plug" against the site's "PLUG" | Brand decision for the owner |
| Three tabs or four | Inbox appears only once the person offers a service; by design |

## 8. Abuse cases (P2.S6)

`tests/phase2` 31–37 cover overlong text, coordinates, budget, timestamps, unknown fields and a
missing key; 48–52 add a reworded refusal, an unlisted service without Claude, and the staff
routes. `tools/phase2-live.mjs` covers rate limits and the reworded refusals.
