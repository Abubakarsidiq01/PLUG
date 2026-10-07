# Live Claude extraction, 6 October 2026

First run with a configured `ANTHROPIC_API_KEY` (backend only, `secrets/anthropic.env`), model
`claude-sonnet-5-5` at low effort, 6-second deadline, rules on any failure (ADR-009).
Server: `tools/run-phase2-local.sh` against `plug_phase2_live`.

## Labelled dataset

All 40 `provider: normal` rows of `fixtures/intents/p2.jsonl` sent to `POST /v1/requests`,
relative times shifted to now as `tools/phase2-live.mjs` does.

| Result | Value |
|---|---|
| Rows agreeing with the label (outcome, category, budget, deadline, question) | 40 / 40 |
| Latency, average / slowest | 1.0 s / 5.2 s |

Per-row results: `claude-live-dataset-2026-10-06.json`. Explicit client fields and unambiguous
rule parses (dollar amounts, relative times) still win over the model, so this shows the
combined path agrees with the labels, not the model alone. One row (`offset-missing`) was first
sent with a zone offset added by the test script; rerun exactly as written, it is the expected
400.

## Free-text asks the rules alone do not read

Through `POST /v1/asks` on the same server:

| Ask | Result |
|---|---|
| "my phone is dead, can someone revive it under $60" | service request, Phone repair, $60 |
| "Someone to regrout my bathroom tiles this weekend" | own-words request "Regrout bathroom tiles", needed by Sunday 23:59 |
| "How packed is the Chick-fil-A on Tech Drive right now?" | place question, "Chick-fil-A on Tech Drive" (the rules read "Tech Drive") |
| "Something" | the one clarifying question |

## Model choice

`claude-opus-5-5` sometimes went past the 6-second deadline (2.1–6.2 s on four asks), so the
rules answered; `claude-sonnet-5-5` gave the same answers in 1.4–3.5 s. Default changed to
Sonnet 5.5 (ADR-009, "Model choice"). Borderline wording can still go either way: on one run
"restring a harp" became Instrument repair, on another the own-words request "Restring a harp".
