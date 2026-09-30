#!/usr/bin/env python3
"""Generate review copies from the same content the web routes render."""
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
data = json.loads((root / 'web/src/content/legal-starter.json').read_text())
for key, doc in data.items():
    text = '# ' + doc['title'] + ' - private-test starter draft\n\n'
    text += 'Prepared September 30, 2026. Not a public-launch agreement; existing consent version unchanged.\n\n'
    text += 'Generated from `web/src/content/legal-starter.json`; edit that shared source and regenerate this review copy.\n\n'
    text += '\n\n'.join('## ' + section['heading'] + '\n\n' + '\n\n'.join(section['paragraphs']) for section in doc['sections']) + '\n'
    (root / f'docs/legal/plug-{key}-starter.md').write_text(text)
