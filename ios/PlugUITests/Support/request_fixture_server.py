#!/usr/bin/env python3
"""Loopback-only synthetic UI-state server. Never a production backend or G2 live evidence.

Run: python3 ios/PlugUITests/Support/request_fixture_server.py
Point RequestScreenshotTests at http://127.0.0.1:18084.
Data comes from the shared contract fixtures; test-only state selection stays outside the app.
The words of the ask choose the state: "clarify", "progress", "empty", "restricted",
"cached", and "line"/"busy" for a place question. Anything else is a service request.
"book" gives live, selectable offers (contract 0.7.x): choosing one makes a pending
reservation that the provider confirms after two polls, or releases with "release", or lets
time out with "timeout"; "cancel" keeps it pending so the asker can cancel it. A provider
whose skill description says "inbox" gets matched requests in every MatchStatus; any other
provider's inbox is empty. "states" in the description also makes the first three inbox loads
slow, rate limited and failing, in that order, for the loading and error screenshots. An optional first argument
sets the port, so two worktrees can each run their own server.
"""
import json
import re
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

FIXTURES = Path(__file__).resolve().parents[3] / "fixtures"


def fixture(folder, name):
    return json.loads((FIXTURES / folder / (name + ".json")).read_text())


def stamp(value):
    return value.isoformat().replace("+00:00", "Z")


# The shared fixtures are written around this moment; "book" and inbox states move every
# time in them by the same amount, so deadlines are live and their order is kept.
ANCHOR = datetime(2026, 10, 1, 20, 0, tzinfo=timezone.utc)
DATE_TIME = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")


def shifted(value, delta):
    if isinstance(value, dict):
        return {key: shifted(item, delta) for key, item in value.items()}
    if isinstance(value, list):
        return [shifted(item, delta) for item in value]
    if isinstance(value, str) and DATE_TIME.match(value):
        return stamp(datetime.fromisoformat(value.replace("Z", "+00:00")) + delta)
    return value


class Handler(BaseHTTPRequestHandler):
    # Two simulators may share this server, so each guest gets its own token and provider
    # profile, and identifiers come from one locked counter.
    requests = {}
    asks = {}
    providers = {}
    inbox_modes = {}
    inbox_faults = {}
    inboxes = {}
    counter = 0
    lock = threading.Lock()

    @staticmethod
    def next_id():
        with Handler.lock:
            Handler.counter += 1
            return Handler.counter

    def caller(self):
        return self.headers.get("Authorization", "")

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
        identifier = f"req_ui-{Handler.next_id()}"
        delta = datetime.now(timezone.utc) - ANCHOR
        request = fixture("requests.get", state)
        if "book" in text.lower():
            request = shifted(request, delta)
        request.update(request_id=identifier, text=text)
        Handler.requests[identifier] = {"request": request, "polls": 0, "mode": text.lower(), "delta": delta}
        return request

    def booking_state(self, identifier, record):
        """The request after an offer was chosen; the provider answers after two polls."""
        record["booking_polls"] += 1
        mode = record["mode"]
        name = "reservation-pending"
        if record["booking_polls"] > 2 and "cancel" not in mode:
            name = "reservation-released" if "release" in mode else "not-confirmed" if "timeout" in mode else "confirmed"
        result = shifted(fixture("requests.get", name), record["delta"])
        result.update(request_id=identifier, text=record["request"]["text"])
        result["reservation"]["offer_id"] = record["chosen"]
        return result

    def inbox(self):
        if self.caller() not in Handler.inboxes:
            delta = datetime.now(timezone.utc) - ANCHOR
            items = []
            if Handler.inbox_modes.get(self.caller()):
                items = shifted(fixture("providers.inbox", "success")["items"], delta)
                # An offer this provider already sent was chosen and waits for their confirmation.
                chosen = shifted(fixture("providers.reservation", "confirmed"), delta)
                chosen.update(match_id="mat_ui-selected", status="selected")
                chosen["reservation"].update(status="pending", confirm_by=stamp(datetime.now(timezone.utc) + timedelta(minutes=10)))
                chosen["reservation"].pop("confirmed_at", None)
                now = datetime.now(timezone.utc)
                # A second open request, then one item for each settled state.
                second = dict(items[0], match_id="mat_ui-open2", request_id="req_ui-open2")
                missed = dict(items[0], match_id="mat_ui-missed", request_id="req_ui-missed", status="expired",
                              notified_at=stamp(now - timedelta(hours=2)), respond_by=stamp(now - timedelta(hours=2) + timedelta(minutes=5)),
                              needed_by=stamp(now - timedelta(hours=1)))
                not_chosen = shifted(fixture("providers.reservation", "released"), delta)
                not_chosen.update(match_id="mat_ui-notchosen", request_id="req_ui-notchosen")
                closed = shifted(fixture("providers.reservation", "confirmed"), delta)
                closed.update(match_id="mat_ui-closed", request_id="req_ui-closed", status="closed")
                closed["reservation"].pop("confirmed_at", None)
                closed["reservation"].update(status="canceled", ended_at=closed["reservation"]["created_at"])
                items = [items[0], second, chosen, items[1], missed, not_chosen, closed]
            Handler.inboxes[self.caller()] = items
        return Handler.inboxes[self.caller()]

    def inbox_item(self, match_id):
        return next((item for item in self.inbox() if item["match_id"] == match_id), None)

    def send_offer(self, request_id, body):
        item = next((item for item in self.inbox() if item["request_id"] == request_id and item["status"] == "open"), None)
        if item is None:
            return self.respond(fixture("requests.send-offer", "never-matched"), 404)
        note = body.get("note")
        if note and re.search(r"@|https?:|www\.|\d{3}[ -.]?\d{3}[ -.]?\d{4}", note):
            return self.respond(fixture("requests.send-offer", "contact-in-note"), 400)
        if item["budget_cents"] is not None and body["price_cents"] > item["budget_cents"]:
            return self.respond(fixture("requests.send-offer", "over-budget"), 400)
        now = datetime.now(timezone.utc)
        start = datetime.fromisoformat(body["available_at"].replace("Z", "+00:00"))
        offer = fixture("requests.send-offer", "success")
        offer.update(price_cents=body["price_cents"], available_at=body["available_at"],
                     observed_at=stamp(now), expires_at=stamp(max(start, now) + timedelta(minutes=15)))
        if note:
            offer["note"] = note
        else:
            offer.pop("note", None)
        item.update(status="offered", offer=offer)
        return self.respond(offer, 201)

    def service_ask(self, ask_id, request):
        return {"ask_id": ask_id, "ask_type": "service_request", "request": request,
                "place_question": None, "clarification": None, "created_at": request["created_at"]}

    def place_ask(self, ask_id, text, status):
        # "no web" in the ask: Unknown with nothing from the web either.
        now = datetime.now(timezone.utc)
        place = {"question_id": ask_id.replace("ask_", "plq_"), "text": text,
                 "place_name": "Walmart on Ben White", "status": status,
                 "progress": {"notified": 3, "opened": 1, "answered": 0}, "answer": None,
                 "web_answer": None, "created_at": stamp(now - timedelta(minutes=1)),
                 "expires_at": stamp(now + timedelta(minutes=9))}
        if status == "unknown" and "no web" not in text:
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
            guest = Handler.next_id()
            return self.respond({"access_token": f"pat_fixture-{guest}", "refresh_token": f"prt_fixture-{guest}",
                "access_token_expires_at": stamp(now + timedelta(hours=1)),
                "refresh_token_expires_at": stamp(now + timedelta(days=1)),
                "account": {"user_id": "usr_ios-fixture", "type": "guest", "scopes": ["guest"]},
                "consent": {"current_version": "2026-09-01", "accepted_version": "2026-09-01", "accepted_at": stamp(now)}}, 201)
        if path == "/v1/asks":
            text = body["text"]
            mode = text.lower()
            if "restricted" in mode:
                return self.respond(fixture("asks.create", "restricted-intent"), 422)
            ask_id = f"ask_ui-{Handler.next_id()}"
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
            if "inbox" in body.get("description", "").lower():
                Handler.inbox_modes[self.caller()] = True
                if "states" in body.get("description", "").lower():
                    Handler.inbox_faults[self.caller()] = ["slow", "rate", "error"]
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
            Handler.providers[self.caller()] = profile
            return self.respond(profile)
        if path.startswith("/v1/providers/me/inbox/"):
            if self.caller() not in Handler.providers:
                return self.respond(fixture("providers.inbox", "not-a-provider"), 404)
            item = self.inbox_item(path.split("/")[5])
            if item is None:
                return self.respond(fixture("providers.decline", "not-found"), 404)
            now = stamp(datetime.now(timezone.utc))
            if path.endswith("/decline"):
                if item["status"] not in ("open", "declined"):
                    return self.respond(fixture("providers.decline", "request-closed"), 409)
                item["status"] = "declined"
                return self.respond(item)
            if path.endswith("/reservation"):
                if item["status"] != "selected":
                    return self.respond(fixture("providers.reservation", "no-reservation"), 409)
                if body["decision"] == "confirm":
                    item["status"] = "confirmed"
                    item["reservation"].update(status="confirmed", confirmed_at=now)
                else:
                    item["status"] = "not_chosen"
                    item["reservation"].update(status="released", ended_at=now)
                return self.respond(item)
        identifier = path.split("/")[3]
        if path.endswith("/offers"):
            return self.send_offer(identifier, body)
        record = self.requests[identifier]
        if path.endswith("/select"):
            if record["request"]["status"] == "user_selected":
                return self.respond(fixture("requests.select", "already-selected"), 409)
            if record["request"]["status"] != "ranked":
                return self.respond(fixture("requests.select", "not-selectable"), 409)
            record.update(chosen=body["offer_id"], booking_polls=0)
            result = shifted(fixture("requests.select", "success"), record["delta"])
            result.update(request_id=identifier, text=record["request"]["text"])
            result["reservation"]["offer_id"] = body["offer_id"]
            record["request"] = result
            return self.respond(result)
        if path.endswith("/cancel"):
            result = fixture("requests.get", "canceled")
            result.update(request_id=identifier, text=record["request"]["text"])
            reservation = record["request"].get("reservation")
            if reservation and reservation["status"] == "pending":
                result["reservation"] = dict(reservation, status="canceled", ended_at=stamp(datetime.now(timezone.utc)))
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
            profile = Handler.providers.get(self.caller())
            if profile is None:
                return self.respond(fixture("providers.me", "not-a-provider"), 404)
            return self.respond(profile)
        if path == "/v1/providers/me/inbox":
            if self.caller() not in Handler.providers:
                return self.respond(fixture("providers.inbox", "not-a-provider"), 404)
            faults = Handler.inbox_faults.get(self.caller())
            fault = faults.pop(0) if faults else None
            if fault == "slow":
                time.sleep(4)
            elif fault == "rate":
                return self.respond(fixture("providers.inbox", "rate-limited"), 429)
            elif fault == "error":
                return self.respond(fixture("providers.inbox", "transient-error"), 500)
            return self.respond({"items": self.inbox(), "notifications_per_hour": 4})
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
            if "book" in record["mode"]:
                result = shifted(fixture("requests.offers", "sms-and-app"), record["delta"])
                if record["request"].get("reservation", {}).get("status") in ("released", "timed_out"):
                    result["offers"] = [offer for offer in result["offers"] if offer["offer_id"] != record["chosen"]]
                result["request_id"] = identifier
                return self.respond(result)
            result = fixture("requests.offers", "business-profile" if "business" in record["mode"] else "success")
            if "sorting" in record["mode"]:
                result["offers"].reverse()
            result["request_id"] = identifier
            return self.respond(result)
        if record["request"]["status"] in ("draft", "canceled", "expired"):
            return self.respond(record["request"])
        if record.get("chosen"):
            if record["request"]["status"] == "user_selected":
                record["request"] = self.booking_state(identifier, record)
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
        if "book" in mode:
            result = shifted(result, record["delta"])
        result.update(request_id=identifier, text=record["request"]["text"])
        record["request"] = result
        self.respond(result)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 18084), Handler).serve_forever()
