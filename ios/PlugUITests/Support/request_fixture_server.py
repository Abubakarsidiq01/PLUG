#!/usr/bin/env python3
"""Loopback-only synthetic UI-state server. Never a production backend or G2 live evidence.

Run: python3 ios/PlugUITests/Support/request_fixture_server.py
Point RequestScreenshotTests at http://127.0.0.1:18084.
Data comes from the shared contract fixtures; test-only state selection stays outside the app.
The words of the ask choose the state: "clarify", "progress", "empty", "restricted",
"cached", and "line"/"busy" for a place question. Anything else is a service request.
"""
import json
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

FIXTURES = Path(__file__).resolve().parents[3] / "fixtures"


def fixture(folder, name):
    return json.loads((FIXTURES / folder / (name + ".json")).read_text())


def stamp(value):
    return value.isoformat().replace("+00:00", "Z")


class Handler(BaseHTTPRequestHandler):
    requests = {}
    asks = {}
    provider = None
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

    def new_request(self, text, state):
        Handler.counter += 1
        identifier = f"req_ui-{Handler.counter}"
        request = fixture("requests.get", state)
        request.update(request_id=identifier, text=text)
        Handler.requests[identifier] = {"request": request, "polls": 0, "mode": text.lower()}
        return request

    def service_ask(self, ask_id, request):
        return {"ask_id": ask_id, "ask_type": "service_request", "request": request,
                "place_question": None, "clarification": None, "created_at": request["created_at"]}

    def place_ask(self, ask_id, text, status):
        now = datetime.now(timezone.utc)
        place = {"question_id": f"plq_ui-{Handler.counter}", "text": text,
                 "place_name": "Walmart on Ben White", "status": status,
                 "progress": {"notified": 3, "opened": 1, "answered": 0}, "answer": None,
                 "web_answer": None, "created_at": stamp(now - timedelta(minutes=1)),
                 "expires_at": stamp(now + timedelta(minutes=9))}
        if status == "unknown":
            # Figure A1 screen 4: what the web says, never promoted above Not verified.
            place["web_answer"] = {"headline": "Usually busy at this hour",
                                   "summary": "Popular-times data says weekday evenings are the busiest. Nobody checked today.",
                                   "source_name": "Synthetic web summary", "retrieved_at": stamp(now - timedelta(minutes=2)),
                                   "truth_label": "not_verified"}
        return {"ask_id": ask_id, "ask_type": "place_question", "request": None, "place_question": place,
                "clarification": None, "created_at": place["created_at"]}

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        path = urlparse(self.path).path
        if path == "/v1/auth/logout":
            self.send_response(204)
            self.end_headers()
            return
        if path == "/v1/auth/guest":
            now = datetime.now(timezone.utc)
            Handler.provider = None
            return self.respond({"access_token": "pat_fixture", "refresh_token": "prt_fixture",
                "access_token_expires_at": stamp(now + timedelta(hours=1)),
                "refresh_token_expires_at": stamp(now + timedelta(days=1)),
                "account": {"user_id": "usr_ios-fixture", "type": "guest", "scopes": ["guest"]},
                "consent": {"current_version": "2026-09-01", "accepted_version": "2026-09-01", "accepted_at": stamp(now)}}, 201)
        if path == "/v1/asks":
            text = body["text"]
            mode = text.lower()
            if "restricted" in mode:
                return self.respond(fixture("asks.create", "restricted-intent"), 422)
            Handler.counter += 1
            ask_id = f"ask_ui-{Handler.counter}"
            if "clarify" in mode:
                result = fixture("asks.create", "clarification")
                result["ask_id"] = ask_id
                Handler.asks[ask_id] = {"text": text, "result": result, "polls": 0}
                return self.respond(result, 201)
            if "answered place" in mode:
                result = fixture("asks.get", "answered")
                result["ask_id"] = ask_id
                place = result["place_question"]
                now = datetime.now(timezone.utc)
                place.update(text=text, created_at=stamp(now - timedelta(minutes=1)),
                             expires_at=stamp(now + timedelta(minutes=9)))
                place["answer"]["expires_at"] = stamp(now + timedelta(minutes=5))
                for index, source in enumerate(place["answer"]["sources"]):
                    source["answered_at"] = stamp(now - timedelta(minutes=index + 1))
                Handler.asks[ask_id] = {"text": text, "result": result, "polls": 0}
                return self.respond(result, 201)
            if "line" in mode or "busy" in mode:
                result = self.place_ask(ask_id, text, "asking")
                Handler.asks[ask_id] = {"text": text, "result": result, "polls": 0}
                return self.respond(result, 201)
            result = self.service_ask(ask_id, self.new_request(text, "submitted"))
            Handler.asks[ask_id] = {"text": text, "result": result, "polls": 0}
            return self.respond(result, 201)
        if path.startswith("/v1/asks/") and path.endswith("/clarifications"):
            ask_id = path.split("/")[3]
            record = Handler.asks[ask_id]
            result = self.service_ask(ask_id, self.new_request(record["text"], "submitted"))
            record["result"] = result
            return self.respond(result)
        if path == "/v1/providers/skills/propose":
            if body.get("description") == "Wig install":
                return self.respond({"error": {"code": "temporarily_unavailable", "message": "Suggestions unavailable", "request_id": "req_ios-fixture"}}, 503)
            return self.respond(fixture("providers.propose", "success"))
        if path == "/v1/providers/skills":
            profile = fixture("providers.skills", "success")
            known = {skill["tag"]: skill for skill in fixture("providers.propose", "success")["skills"]}
            profile.update(skills=[known.get(tag, {"tag": tag, "display": tag.replace("_", " ").capitalize(),
                                                   "requires_licence": False}) for tag in body["skill_tags"]],
                           travel_radius_m=body["travel_radius_m"], availability=body["availability"],
                           accepting=body.get("accepting", True),
                           custom_skills=[label[:1].upper() + label[1:] for label in body.get("custom_skills") or []])
            profile["business"] = body.get("business", {})
            Handler.provider = profile
            return self.respond(profile)
        identifier = path.split("/")[3]
        record = self.requests[identifier]
        if path.endswith("/cancel"):
            result = fixture("requests.get", "canceled")
            result.update(request_id=identifier, text=record["request"]["text"])
            record["request"] = result
            return self.respond(result)
        self.respond({}, 404)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/v1/me":
            return self.respond({
                "account": {"user_id": "usr_ios-fixture", "type": "guest", "scopes": ["guest"]},
                "consent": {"current_version": "2026-09-01", "accepted_version": "2026-09-01",
                            "accepted_at": stamp(datetime.now(timezone.utc))}})
        if path == "/health":
            return self.respond({"status": "UP", "version": "synthetic-ui-fixtures"})
        if path == "/v1/providers/me":
            if Handler.provider is None:
                return self.respond(fixture("providers.me", "not-a-provider"), 404)
            return self.respond(Handler.provider)
        if path.startswith("/v1/asks/"):
            ask_id = path.split("/")[3]
            record = Handler.asks[ask_id]
            record["polls"] += 1
            result = record["result"]
            if result.get("place_question") and result["place_question"]["status"] == "asking" and record["polls"] > 1:
                record["result"] = result = self.place_ask(ask_id, record["text"], "unknown")
            return self.respond(result)
        identifier = path.split("/")[3]
        record = self.requests[identifier]
        if path.endswith("/offers"):
            result = fixture("requests.offers", "business-profile" if "business" in record["mode"] else "success")
            if "sorting" in record["mode"]:
                result["offers"].reverse()
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
