# Phase 2 connected checkpoint, 2026-10-07

Both engineers at the same time against the same backend through public HTTPS tunnels
(ADR-004: a cloudflared quick tunnel is the staging environment until AWS is provisioned).

| | |
|---|---|
| Commit | `1d13b9ed1c3176bf437e41782f8ff2cf1550d7cf` |
| API | https://studios-extend-various-compression.trycloudflare.com |
| Staff console | https://bulletin-bunch-incredible-executed.trycloudflare.com |
| Backend | requests_v2 on `plug_phase2_live`, `db` profile through the tunnel (not the `staging` profile) |
| Modes | Intent extraction: Claude (rules on any failure).; Staff email: local file backend/build/development-staff-mail.txt (set RESEND_API_KEY in secrets/staff.env for real email). |

## Request IDs found in the backend log

| Request ID | In the backend log | Lines | Audit event |
|---|---|---|---|
| `req_2045e385-b43b-444f-9c19-00b4a04b9efe` | found | 1 | restricted_intent:violence |
| `checkpoint-p2-dd81bb0d-1d1b-4cad-a908-13436819ff7f` | found | 1 | — |
| `checkpoint-p2-46a252a2-4eb8-4be8-a382-8b71405ba819` | found | 1 | — |
| `checkpoint-p2-3dc70318-f66b-4436-802e-533dd00eac56` | found | 1 | restricted_intent:violence |

Matching lines: `evidence/P2/logs/connected-checkpoint-2026-10-07.log`.
Person Two's calls: `evidence/P2/windows/2026-10-08/checkpoint.json`, saved on her machine (dated in UTC), to be committed with this record.

## Observed

- **Person One, iPhone 13 Pro Max over mobile data** (PLUG built by the launcher against the
  public API): guest session, a service ask, a place question, then "Pay someone to beat up my
  roommate", refused with support reference `req_2045e385-b43b-444f-9c19-00b4a04b9efe`. That
  reference is in the backend log (422) and on the refusal's audit event.
- **Person Two, her own PC** (`tools/checkpoint-partner.mjs`): all 8 calls passed (health 200,
  guest 201, service ask 201, place question 201, harmful ask 422, guest staff read 403, sign-out
  204, signed-out token 401). Three of her IDs are above; all are in her `checkpoint.json`.
- **Staff console, real accounts:** Person One accepted the owner invitation, signed in with the
  emailed code and invited Person Two from Staff. Person Two accepted, signed in with her own
  emailed code and read the live tables (audit: `staff.joined`, `staff.signed_in`, 5
  `admin.read` for her account). Codes went to the local mail file and were passed privately,
  because staff email delivery (Resend) is not configured yet.
- **Not as planned:** nothing failed. The backend ran the `db` profile through the tunnel, not
  the `staging` profile (ADR-004).

## Signatures

- Person One: Abubakar Bolakale (09/10/2026)
- Person Two: Uzoma Okey (09/10/2026)

Then record G2: `python3 tools/sign-g2.py --record evidence/P2/logs/connected-checkpoint-2026-10-07.md --both-confirm`.
