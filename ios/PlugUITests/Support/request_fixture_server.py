#!/usr/bin/env python3
"""Loopback-only synthetic UI-state server. Never a production backend or G2 live evidence.

Run: python3 ios/PlugUITests/Support/request_fixture_server.py
Point RequestScreenshotTests at http://127.0.0.1:18084.
Data comes from the shared contract fixtures; test-only state selection stays outside the app.
"""
import json
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

FIXTURES = Path(__file__).resolve().parents[3] / "fixtures"


def fixture(folder, name):
    return json.loads((FIXTURES / folder / (name + ".json")).read_text())


class Handler(BaseHTTPRequestHandler):
    records = {}
    counter = 0

    def log_message(self, *args):
        pass  # No tokens, prompts or coordinates in logs.

    def respond(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Request-Id", "req_ios-fixture")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        path = urlparse(self.path).path
        if path == "/v1/auth/guest":
            now = datetime.now(timezone.utc)
            stamp = lambda value: value.isoformat().replace("+00:00", "Z")
            return self.respond({"access_token": "pat_fixture", "refresh_token": "prt_fixture",
                "access_token_expires_at": stamp(now + timedelta(hours=1)),
                "refresh_token_expires_at": stamp(now + timedelta(days=1)),
                "account": {"user_id": "usr_ios-fixture", "type": "guest", "scopes": ["guest"]},
                "consent": {"current_version": "2026-09-01", "accepted_version": "2026-09-01", "accepted_at": stamp(now)}}, 201)
        if path == "/v1/requests":
            text = body["text"]
            if "unsupported" in text.lower():
                return self.respond(fixture("requests.create", "unsupported-category"), 400)
            Handler.counter += 1
            identifier = f"req_ui-{Handler.counter}"
            state = "draft" if "clarify" in text.lower() else "submitted"
            request = fixture("requests.get", state)
            request.update(request_id=identifier, text=text)
            Handler.records[identifier] = {"request": request, "polls": 0, "mode": text.lower()}
            return self.respond(request, 201)
        identifier = path.split("/")[-2]
        record = self.records[identifier]
        if path.endswith("/cancel"):
            result = fixture("requests.get", "canceled")
            result.update(request_id=identifier, text=record["request"]["text"])
            record["request"] = result
            return self.respond(result)
        if path.endswith("/clarifications"):
            result = fixture("requests.get", "submitted")
            result.update(request_id=identifier, text=record["request"]["text"])
            record["request"] = result
            return self.respond(result)
        self.respond({}, 404)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            return self.respond({"status": "UP", "version": "synthetic-ui-fixtures"})
        identifier = path.split("/")[3]
        record = self.records[identifier]
        if path.endswith("/offers"):
            result = fixture("requests.offers", "success")
            result["request_id"] = identifier
            return self.respond(result)
        if record["request"]["status"] in ("draft", "canceled", "expired"):
            return self.respond(record["request"])
        record["polls"] += 1
        mode = record["mode"]
        if "cached" in mode and record["polls"] > 1:
            return self.respond(fixture("requests.get", "transient-error"), 500)
        if "progress" in mode or record["polls"] < 2:
            state = "awaiting-responses"
        elif "empty" in mode:
            state = "empty"
        else:
            state = "success"
        if "cached" in mode:
            state = "success"
        result = fixture("requests.get", state)
        result.update(request_id=identifier, text=record["request"]["text"])
        record["request"] = result
        self.respond(result)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18084), Handler).serve_forever()
