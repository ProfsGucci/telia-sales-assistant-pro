#!/usr/bin/env python3
"""Minimal OpenAI-compatible pass-through proxy for Telia Sales Assistant Pro.

Why: the app never ships API keys in the IPA. Instead it talks to a server
you control (this one), which holds the real upstream key in an environment
variable and forwards /v1/chat/completions — including SSE streaming.

Security model
--------------
- UPSTREAM_URL   – real OpenAI-compatible endpoint (default: api.openai.com)
- UPSTREAM_KEY   – the actual API key, lives only in this server's env
- PROXY_TOKEN    – optional shared secret; if set, the app must send it as
                   `Authorization: Bearer <PROXY_TOKEN>` (Settings → AI-backend
                   → API-nyckel). Requests without it are rejected.
- MODEL_OVERRIDE – optional; forces a specific model regardless of the
                   app's request body.

Endpoints
---------
- GET  /healthz          → liveness probe
- POST /v1/chat/completions → proxied, streaming preserved

Run locally:  PORT=8080 UPSTREAM_KEY=sk-... python3 server.py
Docker:       see Dockerfile in this directory.

No third-party dependencies — standard library only.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
UPSTREAM_URL = os.environ.get("UPSTREAM_URL", "https://api.openai.com").rstrip("/")
UPSTREAM_KEY = os.environ.get("UPSTREAM_KEY", "")
PROXY_TOKEN = os.environ.get("PROXY_TOKEN", "")
MODEL_OVERRIDE = os.environ.get("MODEL_OVERRIDE", "")
MAX_BODY_BYTES = 512 * 1024  # generous; app payloads are small


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ---- helpers -------------------------------------------------------

    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")

    def _respond(self, status: int, payload: dict, content_type="application/json"):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self._cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        if not PROXY_TOKEN:
            return True
        header = self.headers.get("Authorization", "")
        return header == f"Bearer {PROXY_TOKEN}"

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.address_string(), fmt % args))

    # ---- routes --------------------------------------------------------

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self._cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path in ("/healthz", "/"):
            self._respond(200, {"ok": True, "upstream": UPSTREAM_URL, "token_required": bool(PROXY_TOKEN)})
        else:
            self._respond(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._respond(404, {"error": "only /v1/chat/completions is proxied"})
            return

        if not self._authorized():
            self._respond(401, {"error": "invalid or missing proxy token"})
            return

        if not UPSTREAM_KEY:
            self._respond(500, {"error": "server misconfigured: UPSTREAM_KEY is not set"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self._respond(400, {"error": "invalid body size"})
            return
        body = self.rfile.read(length)

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self._respond(400, {"error": "body is not valid JSON"})
            return

        if not isinstance(payload.get("messages"), list) or not payload["messages"]:
            self._respond(400, {"error": "messages[] is required"})
            return
        if MODEL_OVERRIDE:
            payload["model"] = MODEL_OVERRIDE
        payload.setdefault("stream", True)

        request = urllib.request.Request(
            f"{UPSTREAM_URL}/v1/chat/completions",
            data=json.dumps(payload).encode(),
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Accept": "text/event-stream" if payload["stream"] else "application/json",
                "Authorization": f"Bearer {UPSTREAM_KEY}",
            },
        )

        try:
            upstream = urllib.request.urlopen(request, timeout=120)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:1000]
            self._respond(exc.code, {"error": f"upstream {exc.code}", "detail": detail})
            return
        except Exception as exc:  # network failure, timeout, DNS
            self._respond(502, {"error": f"upstream unreachable: {exc}"})
            return

        with upstream:
            self.send_response(upstream.status)
            self.send_header("Content-Type", upstream.headers.get("Content-Type", "application/json"))
            self.send_header("Cache-Control", "no-cache")
            if payload["stream"]:
                self.send_header("Transfer-Encoding", "chunked")
                self._cors_headers()
                self.end_headers()
                try:
                    while True:
                        chunk = upstream.read(1024)
                        if not chunk:
                            break
                        self.wfile.write(b"%x\r\n" % len(chunk) + chunk + b"\r\n")
                        self.wfile.flush()
                    self.wfile.write(b"0\r\n\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass  # client cancelled (app closed / user stopped)
            else:
                data = upstream.read()
                self.send_header("Content-Length", str(len(data)))
                self._cors_headers()
                self.end_headers()
                self.wfile.write(data)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"openai-proxy listening on :{PORT} → {UPSTREAM_URL}"
          f" (token required: {bool(PROXY_TOKEN)}, model override: {MODEL_OVERRIDE or 'none'})",
          flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
