#!/usr/bin/env python3
"""Save a current development tunnel URL without printing or changing OAuth credentials."""
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 tools/set-phone-api.py https://YOUR-TUNNEL.trycloudflare.com')
url = sys.argv[1].rstrip('/')
parsed = urlsplit(url)
if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
        or parsed.query or parsed.fragment or parsed.path or not re.fullmatch(r'https://[A-Za-z0-9.-]+', url)):
    raise SystemExit('Use an HTTPS server origin with no path, credentials, query or fragment.')
root = Path(__file__).resolve().parent.parent
path = root / 'ios/Plug/Resources/Local.xcconfig'
body = path.read_text() if path.exists() else ''
# xcconfig treats // as a comment; an empty expansion preserves the URL at build time.
line = 'PLUG_DEVELOPMENT_API_URL = ' + url.replace('://', ':/$()/')
pattern = r'^PLUG_DEVELOPMENT_API_URL\s*=.*$'
body = re.sub(pattern, line, body, flags=re.M) if re.search(pattern, body, re.M) else body.rstrip() + '\n' + line + '\n'
path.write_text(body)
path.chmod(0o600)
print('Saved phone API address. Rebuild PLUG to apply it; OAuth settings were preserved.')
