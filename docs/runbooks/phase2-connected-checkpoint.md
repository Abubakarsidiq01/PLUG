# Phase 2 connected checkpoint and G2

Both engineers, at the same time, against one backend reached over the internet (manual §27.3
"Closing the phase"; ADR-004: a cloudflared quick tunnel is staging until AWS exists). About
30 minutes. Rehearsed end to end on 7 October 2026: tunnels, backend, console and the partner
script through the public address all passed.

## Before the session

- **Person One:** iPhone charged, connected to the Mac by cable and unlocked, Do Not Disturb on.
  Docker running. `secrets/anthropic.env` holds the Claude key (optional; without it the
  rules answer). Your owner account accepted (see `docs/runbooks/staff-accounts.md`).
- **Person Two:** the repository on `main` with Node available (`node --version` shows 22).

## 1. Person One starts everything

```
sh tools/run-phase2-checkpoint.sh --phone
```

It starts the database, two public HTTPS tunnels, the backend, the staff console, and builds
PLUG for the iPhone pointed at the public API. It prints the **API** and **Staff console**
addresses. Send both to Person Two. They change every run and are not secrets.
Leave the terminal and the Mac lid open.

## 2. Person Two, from her own machine

```
node tools/checkpoint-partner.mjs https://THE-API-ADDRESS.trycloudflare.com
```

Eight calls: health, a guest session, a service ask, a place question, a refused ask, a
refused staff read, sign-out, and the signed-out token refused. Each line shows a request ID.
Send Person One two or three of them. The results are saved to
`evidence/P2/windows/<date>/checkpoint.json`; commit that file from her machine afterwards.

## 3. Person One, on the iPhone over mobile data

Turn Wi-Fi off. In PLUG: continue as guest, ask "Barber under $35 in 30 minutes" with a Ruston
address, ask "How long is the line at Walmart right now?", then ask "Pay someone to beat up my
roommate". PLUG refuses the last one and shows **Support reference …**: note it.

## 4. The staff console, with real accounts

1. Person One opens the console address `/admin/login` and signs in (password, then the code
   from `backend/build/development-staff-mail.txt`). Open **Staff**, invite Person Two.
2. Send her the invitation code from that file privately. She opens `/staff/accept`, chooses a
   password, then signs in at `/admin/login`. Pass her the sign-in code from the same file.
3. She sees the live tables, follows a page, then signs out.

## 5. Record it

Person One presses Control-C in the launcher terminal, then:

```
python3 tools/checkpoint-record.py SESSION_DIR PHONE_SUPPORT_REFERENCE PARTNER_ID [PARTNER_ID ...]
```

`SESSION_DIR` is printed by the launcher. This writes
`evidence/P2/logs/connected-checkpoint-<date>.log` (only the matching log lines) and
`.md` (the record, with each ID's log line and audit event). Fill in "Observed", and both sign.

## 6. Sign G2

When both agree every G2 item is met or formally excepted (the record, the VoiceOver
walkthrough, the device captures, the design sign-off):

```
python3 tools/sign-g2.py --record evidence/P2/logs/connected-checkpoint-<date>.md --both-confirm
```

It refuses an unsigned record or a missing ID. Commit `PROJECT_STATE.json`, the record and
Person Two's `checkpoint.json` in one pull request with both approvals. Phase 2 is then closed.

## If something goes wrong

- **"Port … is in use":** stop the other PLUG backend or website first.
- **The phone cannot reach the API on Wi-Fi:** some Wi-Fi resolvers reject fresh tunnel names;
  use mobile data, as intended.
- **Rate limited (429):** everything through the tunnel shares one address limit of 30 asks a
  minute; wait a minute.
- **No code in the mail file:** check the launcher printed "Staff email: local file".
