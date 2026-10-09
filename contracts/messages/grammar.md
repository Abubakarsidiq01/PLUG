# Inbound reply grammar, v1

**Proposed with contract 0.7.0.** A grammar, not a language model (manual §19.8). The
keyword sets and limits are in [grammar.v1.json](grammar.v1.json); the regression cases are
in [cases.v1.json](cases.v1.json). The backend parser (P3.S5) loads both and must pass every
case. Copy in [templates.v1.json](templates.v1.json) tells suppliers what to send, so the
copy, this grammar and the cases change together, in one pull request.

## Order of evaluation

The first rule that matches decides. Before any of them, a `MessageSid` seen in the last 7
days is `duplicate` and nothing else happens.

Normalising is listed in `normalise`; "word" below always means a word with its leading and
trailing punctuation removed, so `No, busy today` starts with `NO`.

1. **Empty.** Nothing left after normalising: `unparseable`.
2. **Opt out.** The whole message is one of `opt_out_exact`, or any word (letters only, edge
   punctuation removed) is one of `opt_out_anywhere`, or the message contains `OPT OUT`:
   `stop`. This is deliberately loose. Wrongly opting someone out costs one START; wrongly
   texting someone who said stop is a compliance failure.
3. **Opt in.** The whole message is one of `opt_in_exact`: `start`.
4. **Help.** The first word is one of `help_first`: `help`.
5. **Pause.** The first word is `PAUSE`: `pause` for `pause_hours`.
6. Steps 2 to 5 work from any number, known or not, and in any context. From here on the
   reply is read against the sender's **open context**. A supplier has at most one (the
   matcher skips anyone with one open), so a bare YES or CONFIRM is never ambiguous. With
   none: `no_open_context`.
7. **Reservation context** (the asker picked this supplier's offer):
   - First word in `confirm_first`, optionally followed by the booking ref, and nothing else:
     `confirm`. A ref that is not this reservation's: `unparseable`.
   - First word in `release_first`, optionally followed by the ref, and nothing else:
     `release`.
   - Anything else: `unparseable`.
8. **Outreach context** (PLUG asked for an offer):
   - First word in `decline_first`: `decline`. The rest is ignored.
   - `YES|Y`, then a price, then a time, and nothing else: `offer`, subject to the checks
     below.
   - `YES|Y` alone, or followed only by a price, or only by a time: `incomplete`.
   - Anything else, including a price or time PLUG cannot read: `unparseable`.

## Price and time

- **Price** is whole dollars, an optional `$`, and optional cents (`30`, `$30`, `32.50`),
  between `price_dollars.min` and `.max`. Outside that range: `unparseable`. Above the
  request's budget: `over_budget`.
- **Time** is read in the supplier's own time zone and must be one of `time_forms`. Every
  time means its next occurrence not before the reply, compared at the minute, so it is
  always within 24 hours; `2:15` without AM or PM is whichever of 2:15 AM and 2:15 PM comes
  first. `NOW` is the reply time rounded up to the next minute. A bare hour without AM or PM
  (`YES 30 2`) is `unparseable`. A time after the request's `needed_by`: `outside_window`.
  A reply that names a time already gone today therefore lands tomorrow, and the
  `offer_received` text shows the day so the supplier can see it.

## What each result does

| Result | Request | Offer | Supplier score | Reply sent |
|---|---|---|---|---|
| `offer` | counts as replied | exactly one, enforced by the database | responsive | `offer_received` |
| `decline` | counts as replied | none | responsive, never a penalty | none |
| `confirm` | `user_selected` to `confirmed` | unchanged | — | `booked` |
| `release` | back to `ranked`, or `expired` (`not_confirmed`) | withdrawn | — | `released` |
| `stop` | supplier's open context closes | none | none | `stop_confirm` |
| `start` | — | — | — | `optin_confirmed` |
| `pause` | open context closes | none | none | `pause_confirm` |
| `help` | — | — | — | `help` |
| `incomplete` | nothing | none | none | `offer_incomplete`, once |
| `over_budget` | nothing | none | none | `offer_over_budget`, once |
| `outside_window` | nothing | none | none | `offer_outside_window`, once |
| `unparseable` | nothing | none | none | `unparseable`, once |
| `no_open_context` | nothing | none | none | `request_closed` if a context closed in the last `late_reply_memory_hours`, once; otherwise none |
| `duplicate` | nothing | none | none | none |

"Once" is `hint_replies_per_context`: after one hint, further failed replies in the same
context get silence, which also stops two auto-responders texting each other forever. A
correct reply after a hint is still accepted.

## Twilio's own keyword handling

The Messaging Service uses Advanced Opt-Out configured with exactly `opt_out_exact`,
`opt_in_exact` and `help_first`, and with the `stop_confirm`, `optin_confirmed` and `help`
texts from templates.v1.json. Twilio's default opt-in word `YES` is removed, because YES is
an offer here. Twilio only acts when the whole message is the keyword: then Twilio sends the
reply and PLUG does not. For a looser match (an opt-out word inside a sentence, `help me`)
PLUG sends the same text itself. Each case in cases.v1.json says which (`reply_by`). PLUG's own suppression list
is the authority either way, and it is checked again at send time.
