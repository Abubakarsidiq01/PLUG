#!/usr/bin/env python3
"""Turn a Phase 2 checkpoint session into evidence (manual §27.3, evidence/P2/logs).

    python3 tools/checkpoint-record.py SESSION_DIR REQUEST_ID [REQUEST_ID ...]

SESSION_DIR is what tools/run-phase2-checkpoint.sh printed. Each REQUEST_ID is a correlation
ID: the "Support reference" the iPhone shows when PLUG refuses an ask, or one printed by
tools/checkpoint-partner.mjs on Person Two's machine.
Writes only the backend log lines that carry those IDs (the log holds routes, statuses and
references, never people's words, locations or tokens), plus a record to complete and sign.
"""
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

if len(sys.argv) < 3:
    raise SystemExit(__doc__)
session = Path(sys.argv[1])
wanted = sys.argv[2:]
for value in wanted:
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', value):
        raise SystemExit(f'Not a request ID: {value!r}')
log = session / 'backend.log'
if not log.exists():
    raise SystemExit(f'No backend log in {session}')

lines = log.read_text(errors='replace').splitlines()
found = {value: [line for line in lines if f'request_id={value}' in line] for value in wanted}
day = datetime.date.today().isoformat()
root = Path(__file__).resolve().parent.parent
folder = root / 'evidence' / 'P2' / 'logs'
folder.mkdir(parents=True, exist_ok=True)
addresses = (session / 'addresses.txt').read_text().split() if (session / 'addresses.txt').exists() else ['?', '?']
commit = (session / 'commit.txt').read_text().strip() if (session / 'commit.txt').exists() else '?'
# Without the local file path: this goes into the repository.
mode = [re.sub(r' \S*/development-staff-mail\.txt', ' backend/build/development-staff-mail.txt', line.strip())
        for line in lines if 'Intent extraction:' in line or 'Staff email:' in line]


def audited(value):
    """The refusal's audit event carries the same correlation ID: a second, independent record."""
    try:
        out = subprocess.run(['docker', 'exec', 'plug-phase2-validation', 'psql', '-U', 'plug', '-d', 'plug_phase2_live', '-Atc',
                              f"SELECT reason FROM audit_events WHERE request_id = '{value}' ORDER BY id"],
                             capture_output=True, text=True, timeout=20).stdout.split()
    except Exception:
        return '?'
    return ', '.join(out) or '—'


matched = folder / f'connected-checkpoint-{day}.log'
with matched.open('w') as out:
    out.write(f'# Phase 2 connected checkpoint {day}, commit {commit}\n# API {addresses[0]}  console {addresses[1]}\n')
    for value, hits in found.items():
        out.write(f'\n# {value}: {len(hits)} line(s)\n')
        out.writelines(hit + '\n' for hit in hits)

partner = sorted(root.glob('evidence/P2/windows/*/checkpoint.json'))
partner_report = json.loads(partner[-1].read_text()) if partner else None
record = folder / f'connected-checkpoint-{day}.md'
rows = '\n'.join(f'| `{value}` | {"found" if hits else "NOT FOUND"} | {len(hits)} | {audited(value)} |'
                 for value, hits in found.items())
record.write_text(f'''# Phase 2 connected checkpoint, {day}

Both engineers at the same time against the same backend through public HTTPS tunnels
(ADR-004: a cloudflared quick tunnel is the staging environment until AWS is provisioned).

| | |
|---|---|
| Commit | `{commit}` |
| API | {addresses[0]} |
| Staff console | {addresses[1]} |
| Backend | requests_v2 on `plug_phase2_live`, `db` profile through the tunnel (not the `staging` profile) |
| Modes | {'; '.join(mode) or 'see backend log'} |

## Request IDs found in the backend log

| Request ID | In the backend log | Lines | Audit event |
|---|---|---|---|
{rows}

Matching lines: `{matched.relative_to(root)}`.
Person Two's calls: `{partner[-1].relative_to(root) if partner else 'evidence/P2/windows/<date>/checkpoint.json (commit it from her machine)'}`{'' if not partner_report else f" ({'all passed' if partner_report['passed'] else 'some failed'})"}.

## Observed (fill in)

- Person One, iPhone over mobile data: the asks made, what showed, the support reference noted.
- Person Two, her own machine: `tools/checkpoint-partner.mjs` result; staff console signed in
  with her own account (invitation, emailed code), tables shown, Sign out.
- Anything that did not work, and what was done about it.

## Signatures

- Person One: ______ (date)
- Person Two: ______ (date)

Then record G2: `python3 tools/sign-g2.py --record {record.relative_to(root)} --both-confirm`.
''')
print(f'Wrote {matched.relative_to(root)} and {record.relative_to(root)}')
missing = [value for value, hits in found.items() if not hits]
if missing:
    print('Not in the backend log: ' + ', '.join(missing) + '. Check the ID and that it was made during this session.')
    sys.exit(1)
