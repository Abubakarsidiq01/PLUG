# Supplier messages

**Wording owned by Person Two** (P3-TWO.S1); the parser that reads replies is Person One's
(P3.S5). Proposed with contract 0.7.0. Copy and parser are one artefact: they change together,
in one pull request, with the regression cases updated (manual §27.4).

| File | What it is |
|---|---|
| [templates.v1.json](templates.v1.json) | Every SMS PLUG sends a supplier, and the provider push alert, with each placeholder's maximum length |
| [grammar.md](grammar.md) | How a reply is read, in order, and what each result does |
| [grammar.v1.json](grammar.v1.json) | The keyword sets and limits the parser loads |
| [cases.v1.json](cases.v1.json) | The regression cases: reply, context, expected result, price and time |

`pnpm test:contracts` checks them together (`tests/contracts/messages.test.mjs`): every SMS
rendered with its longest placeholders fits two GSM-7 segments (306 characters) and uses no
character outside the GSM-7 basic set; every template that asks for a reply names only words
the grammar reads; every outreach and opt-in text says who is texting and how to stop; every
case uses a context and a result the contract defines.

## Rules for the copy

- Starts with `PLUG:` so the supplier knows who is texting (HELP text excepted, which starts
  with PLUG).
- Says what is wanted and how to answer, in the words the grammar reads.
- Says how to stop on every outreach and on the opt-in text.
- Never carries the asker's words, name, phone number or location. A booking is identified
  by its four-character ref.
- No emoji, curly quotes or dashes: one of those turns a text into UCS-2 and halves its
  length.

## Consent

`consent_version` in templates.v1.json is the SMS terms version the opt-in form shows and
`POST /v1/suppliers/opt-in` accepts. Changing the opt-in wording or the terms means a new
version, and suppliers who agreed to the old one keep that record. Consent is given only by
the supplier texting START from the number; a form or a member of staff can never give it.

## Changing a template or the grammar

1. Change the copy, the grammar and the cases in one pull request.
2. A new template version (`outreach.v2`) is a contract change with both approvals; fixing a
   typo inside a version is not, but still needs the tests green.
3. If a change alters what a supplier must type, add cases for the old and new forms and keep
   accepting the old form until every queued message using it has expired.
