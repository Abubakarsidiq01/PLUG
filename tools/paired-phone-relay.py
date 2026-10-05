#!/usr/bin/env python3
# Private development only; no public listener, no credentials or resource IDs in logs.
import http.client
import ipaddress
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import argparse

parser = argparse.ArgumentParser(description="Relay a loopback API only to one paired iPhone.")
parser.add_argument("--host", required=True)
parser.add_argument("--peer", required=True)
parser.add_argument("--port", type=int, default=18086)
parser.add_argument("--upstream-port", type=int, default=18085)
args = parser.parse_args()
HOST = args.host
network = ipaddress.ip_network("fd00::/8")
if (ipaddress.ip_address(HOST) not in network or ipaddress.ip_address(args.peer) not in network
        or ipaddress.ip_network(HOST + "/64", strict=False) != ipaddress.ip_network(args.peer + "/64", strict=False)
        or ipaddress.ip_address(HOST) == ipaddress.ip_address(args.peer)):
    parser.error("Use distinct host/phone ULA addresses on the same paired /64 interface.")
if not (1024 <= args.port <= 65535 and 1024 <= args.upstream_port <= 65535):
    parser.error("Ports must be between 1024 and 65535.")
PEER = ipaddress.ip_address(args.peer)
LOCAL = ipaddress.ip_address(HOST)
class Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True
class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass
    def relay(self):
        if ipaddress.ip_address(self.client_address[0]) not in (PEER, LOCAL):
            self.send_error(403); return
        path = self.path.split('?', 1)[0]
        if not (path == '/health' or path.startswith('/v1/')):
            self.send_error(404); return
        if self.headers.get('Transfer-Encoding'):
            self.send_error(400); return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size < 0 or size > 98304:
                self.send_error(413); return
            self.connection.settimeout(20)
            body = self.rfile.read(size) if size else None
            if body is not None and len(body) != size:
                self.send_error(400); return
            headers = {key: self.headers[key] for key in ('Authorization', 'Content-Type', 'Accept', 'Idempotency-Key', 'X-Request-Id') if self.headers.get(key)}
            upstream = http.client.HTTPConnection('127.0.0.1', args.upstream_port, timeout=20)
            try:
                upstream.request(self.command, self.path, body, headers)
                result = upstream.getresponse()
                payload = result.read(2097153)
                if len(payload) > 2097152:
                    self.send_error(502); return
                self.send_response(result.status)
                for key in ('Content-Type', 'X-Request-Id', 'Retry-After', 'Cache-Control'):
                    value = result.getheader(key)
                    if value is not None: self.send_header(key, value)
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                print(self.command, 'health' if path == '/health' else 'api', result.status, flush=True)
            finally:
                upstream.close()
        except (ValueError, OSError, http.client.HTTPException):
            self.send_error(502)
    do_GET = do_POST = do_DELETE = relay
print('Paired-device-only relay on [' + HOST + ']:' + str(args.port) + '; accepts only paired iPhone and host self-checks', flush=True)
Server((HOST, args.port), Handler).serve_forever()
