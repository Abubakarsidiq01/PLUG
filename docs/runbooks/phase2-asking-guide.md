# What people can ask PLUG, and what happens — QA and support guide (Phase 2)

Manual v4 P2-TWO.S5. Written for QA and support. It describes the behaviour on `main`
(contract 0.6.0) with the built-in rules; when a Claude key is configured, Claude reads
unusual wording onto the same skills and the same limits still apply.

## One field, two kinds of ask

| The person writes | PLUG treats it as | What they see |
|---|---|---|
| A job for a person: "Someone to do knotless braids, $120 max", "I need to repair my shoe for $45 tomorrow" | **Service request** | "Asking … nearby", real counts (notified, replied, offers), then offers or No offers |
| What is happening at a public place: "How long is the line at Walmart right now?", "Is the DMV busy?" | **Place question** | Real counts, then an answer from people nearby or **Unknown**. Live answers arrive in Phase 4, so today it ends Unknown; any web summary is dashed and marked Not verified |
| Something unclear: "Something", "help" | **One question** | "What would you like PLUG to do?" with common services and "Something happening at a place". PLUG never asks a second question |

## How a service is recognised

- PLUG lists **115 skills** (`contracts/skills.yaml`): hair and beauty, repairs and tech, home
  trades, vehicles, events and food, creative and digital, lessons, pets and errands.
- It understands the listed names, their synonyms, plurals, and the action-first way people
  speak: "I repair phones", "fix my laptop", "walk dogs", "mount TVs".
- **Providers' own skills.** If no listed skill matches, PLUG checks skills providers described
  in their own words. A one-word skill needs that word in the ask; a longer one needs at least
  two of its words ("sweep my chimney" finds "Chimney sweeping"; "my chimney" alone does not).
- **The asker's own words (0.6.0).** If nothing listed and nothing a provider described
  matches, but the sentence is clearly a job for a person, PLUG creates the request under
  the asker's words: "Someone to regrout my bathroom tiles under $80" becomes a request
  called "Regrout bathroom tiles". It reaches only providers whose own-words skills share
  its keywords.
- Nothing matched and the sentence is not clearly a job → the one question above. PLUG
  never picks a listed skill by guessing.

## Money, time and distance in the words

| Kind | Understood | Limits and errors (shown to the person) |
|---|---|---|
| Budget | "$35", "$1,200", "45 dollars", "60 bucks" | $5 to $5,000. "$1,00" → "Write the budget as dollars and cents." Two different amounts → "Choose one budget." |
| Time | "in 30 minutes", "in 2 hours", "in 3 days", "today", "tonight", "tomorrow", "tomorrow morning/afternoon/evening" | Must be in the future and within 7 days. Morning means by noon, afternoon by 5 pm, evening and tonight by 9 pm, a bare day by 11:59 pm, in the person's time zone. Two different times → "Choose one time." |
| Distance | "within 3 miles", "within 5 km" | 100 m to about 30 miles; otherwise 10 km is used |

## What is refused, and how

Refusals return **"PLUG cannot help with this request. Nobody was contacted."** Nothing is created,
nobody is contacted, and the rule (never the text) is written to the audit log.

| Rule | Examples |
|---|---|
| `illegal_goods` | drugs, stolen goods |
| `weapons` | guns, ammunition (ordinary tools are fine: "bath bombs", "nail gun" for a handyman) |
| `violence` | hurting or killing someone |
| `sexual_services` | escorts, "happy ending" |
| `fraud_cyber` | hacking, phishing, cracking passwords |
| `stalking_tracking` | tracking a partner, finding where someone lives, "is anyone at her house" |
| `unsupported_regulated` | childcare, elder care, medical, legal or financial advice — refused until a safety policy exists |
| `private_place` | a place question about a private home ("How busy is it at her apartment?") |

Licensed trades (electrical, HVAC, licensed plumbing, roofing, pest control, locksmith, tattoo,
piercing, facials, massage, driving lessons) are **not** refused: the request is created with
"licence required", and only providers who gave a licence number are matched.

## When nobody can help

- **No provider covers the service nearby** → "No offers — Nobody on PLUG offers this near you
  yet", with real counts ("Nobody was notified"), and an invitation: "Is this something you do?
  Offer this service".
- **People were notified but nobody offered in time** → No offers with the real counts.
- **A place nobody could check** → Unknown with the number of people notified.

PLUG never shows an invented price, time, provider, review or answer.

## Seeded test data (private preview only)

Example offers exist only for barber and beauty in the synthetic Ruston, LA zone (for example,
type the address "Railroad Ave, Ruston, LA"). They are labelled "Demo offer · Booking isn't
available yet". Elsewhere a request ends honestly with No offers unless a real provider nearby
offers that skill.

## Known gaps (found 2026-10-05, rerun 2026-10-06 on contract 0.6.0)

The examples in this guide are tested as the `guide-` rows of `fixtures/intents/asks.jsonl`.
The full results are in `docs/testing/phase2-person-two-review-2026-10-05.md` and
`docs/testing/phase2-person-two-rerun-2026-10-06.md`.

- **Not refused does not mean approved.** The refusal rules match listed phrases. The same
  request in other words is not refused. Fifteen such cases are recorded. Since 0.6.0 most
  of them no longer get the one question: nine become a real request, eight of them in
  the asker's own words. "Pay someone to beat up my roommate" is created as a request
  called "Pay beat roommate". If a tester sees one, file it with the support reference; do
  not treat the result as permission.
- **Plain descriptions of a listed service miss the listed skill.** "My kitchen sink is
  leaking, who can fix it today?" is now a request in the asker's words instead of the
  listed minor plumbing skill, so a provider who chose that listed skill is not matched.
  "Mount a 55 inch TV on my wall" still gets the one question.
- **"Tonight" after 9 pm.** Tonight means by 9 pm. Two asks that said "tonight" were sent
  after 9 pm local time and were rejected with "Choose a future time."
- **"Is the DMV busy?"** is treated as a place question, but no place name is recorded.
  "Is the DMV line long this morning?" gets the one question.

## Support references

Every error shows a support reference (the request ID). Search the backend log for it; logs
hold the route, status and reference, never the person's words or location.
