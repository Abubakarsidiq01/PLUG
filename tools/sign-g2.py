#!/usr/bin/env python3
"""Append the signed G2 entry to PROJECT_STATE.json (manual §27.3 "Closing the phase").

    python3 tools/sign-g2.py --record evidence/P2/logs/connected-checkpoint-DATE.md --both-confirm

Run only when both engineers have read the checkpoint record and agree that every G2 item is
met or formally excepted. --both-confirm is that statement; without it nothing is written and
the entry is only shown.
"""
import argparse
import datetime
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--record', required=True, help='the completed checkpoint record')
parser.add_argument('--both-confirm', action='store_true', help='both engineers confirm G2 is met')
args = parser.parse_args()

root = Path(__file__).resolve().parent.parent
record = root / args.record
if not record.exists():
    raise SystemExit(f'No record at {args.record}')
text = record.read_text()
if '| NOT FOUND |' in text:
    raise SystemExit('The record has a request ID missing from the backend log. Resolve it first.')
if '______' in text:
    raise SystemExit('The record is not signed yet: fill in both signature lines.')
ids = re.findall(r'\| `([A-Za-z0-9_-]+)` \| found \|', text)
commit = (re.search(r'\| Commit \| `([0-9a-f]+)` \|', text) or [None, '?'])[1]

entry = {
    'gate': 'G2',
    'date': datetime.date.today().isoformat(),
    'manual_section': '27.3',
    'signed_by': ['person_one', 'person_two'],
    'summary': (f'Live, two-person connected checkpoint against the shared backend through public HTTPS tunnels '
                f'(ADR-004) at commit {commit}. Request IDs from the iPhone and from Person Two\'s machine were found '
                f'in the same backend log: {", ".join(ids)}. Contract 0.6.1 merged with both approvals.'),
    'evidence': [args.record, args.record.replace('.md', '.log'), 'docs/testing/phase2-person-one-fixes-2026-10-07.md',
                 'docs/testing/phase2-person-two-rerun-2026-10-06.md'],
}
print(json.dumps(entry, indent=2))
if not args.both_confirm:
    print('\nShown only. Add --both-confirm once both engineers agree, to write it to PROJECT_STATE.json.')
    raise SystemExit(0)
state_path = root / 'PROJECT_STATE.json'
state = json.loads(state_path.read_text())
if any(item.get('gate') == 'G2' for item in state.get('gate_log', [])):
    raise SystemExit('PROJECT_STATE.json already has a G2 entry.')
state['gate_log'].append(entry)
state['last_gate_passed'] = 'G2'
if 'P2' not in state.get('completed_phases', []):
    state.setdefault('completed_phases', []).append('P2')
state['updated_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
state['updated_by'] = 'person_one and person_two (G2 signed)'
state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + '\n')
print('\nG2 recorded in PROJECT_STATE.json. Commit it with the record and open a pull request for both approvals.')
