#!/usr/bin/env python3
"""Termux-side build bridge for the ToolChain native lane.

A deliberately small single-purpose HTTP server that lets the and-code
PRoot environment (same device, shared loopback) execute build commands
natively in Termux - outside any PRoot - and exchange files with the
workspace. NOT a general remote shell: only the endpoints below, bound
to 127.0.0.1, token-gated, all file paths confined to the workspace.

Endpoints:
  GET  /health                 -> {ok, uptime, workspace, busy}
  POST /run   {cmd, cwd, env, timeout}
                              -> {exit_code, duration, tail}  (synchronous,
                                 single worker - one job at a time)
  GET  /file?path=REL          -> file bytes from the workspace
  POST /file  {path, b64}      -> write a file into the workspace

Auth: shared token. On first start a random token is written to
  /sdcard/ToolChain-bridge/token
where the client side (and-code) reads it. Override with
TERMUX_BRIDGE_TOKEN / --token. Override port with --port (default 8042).

Run it in Termux:  python bridge-server.py --workspace ~/ToolChain
Keep Termux alive while building (termux-wake-lock recommended).
"""
import argparse
import base64
import json
import os
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = ""
WORKSPACE = ""
TOKEN_FILE = "/sdcard/ToolChain-bridge/token"
START = time.time()
LOCK = threading.Lock()  # serialize jobs: one build at a time
MAX_BODY = 64 * 1024 * 1024
OUTPUT_TAIL_LINES = 400


def ws_path(rel: str) -> str:
    """Resolve a workspace-relative path, refusing escapes."""
    root = os.path.realpath(WORKSPACE)
    p = os.path.realpath(os.path.join(root, rel))
    if p != root and not p.startswith(root + os.sep):
        raise PermissionError(f"outside workspace: {rel}")
    return p


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(f"[bridge] {self.command} {self.path} from {self.client_address[0]}")

    # -- helpers ----------------------------------------------------------
    def _json(self, code: int, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        return self.headers.get("X-Bridge-Token", "") == TOKEN

    def _body(self) -> bytes:
        n = int(self.headers.get("Content-Length", "0"))
        if n > MAX_BODY:
            raise ValueError("body too large")
        return self.rfile.read(n) if n else b""

    # -- routing ----------------------------------------------------------
    def do_GET(self):
        if not self._authorized():
            return self._json(403, {"error": "bad token"})
        if self.path == "/health":
            return self._json(200, {
                "ok": True,
                "uptime_s": int(time.time() - START),
                "workspace": WORKSPACE,
                "busy": LOCK.locked(),
            })
        if self.path.startswith("/file?path="):
            rel = self.path[len("/file?path="):]
            try:
                p = ws_path(rel)
                with open(p, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except Exception as e:
                return self._json(404, {"error": str(e)})
            return
        return self._json(404, {"error": "no such endpoint"})

    def do_POST(self):
        if not self._authorized():
            return self._json(403, {"error": "bad token"})
        try:
            req = json.loads(self._body())
        except Exception as e:
            return self._json(400, {"error": f"bad request: {e}"})

        if self.path == "/file":
            try:
                p = ws_path(req["path"])
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "wb") as f:
                    f.write(base64.b64decode(req["b64"]))
                return self._json(200, {"ok": True, "path": req["path"]})
            except Exception as e:
                return self._json(400, {"error": str(e)})

        if self.path == "/run":
            cmd = req.get("cmd", "")
            if not isinstance(cmd, str) or not cmd.strip():
                return self._json(400, {"error": "empty cmd"})
            timeout = min(int(req.get("timeout", 3600)), 4 * 3600)
            cwd = ws_path(req.get("cwd", "."))
            env = dict(os.environ)
            env.update({k: str(v) for k, v in (req.get("env") or {}).items()})
            if not LOCK.acquire(blocking=False):
                return self._json(409, {"error": "busy - a job is already running"})
            try:
                t0 = time.time()
                proc = subprocess.run(
                    ["/data/data/com.termux/files/usr/bin/bash", "-lc", cmd],
                    cwd=cwd, env=env, timeout=timeout,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                )
                out = proc.stdout.decode(errors="replace")
                tail = "\n".join(out.splitlines()[-OUTPUT_TAIL_LINES:])
                return self._json(200, {
                    "exit_code": proc.returncode,
                    "duration_s": round(time.time() - t0, 1),
                    "tail": tail,
                })
            except subprocess.TimeoutExpired:
                return self._json(200, {"exit_code": 124, "error": "timeout"})
            finally:
                LOCK.release()
        return self._json(404, {"error": "no such endpoint"})


def main():
    global TOKEN, WORKSPACE
    ap = argparse.ArgumentParser()
    ap.add_argument("--workspace", default=os.path.expanduser("~/ToolChain"))
    ap.add_argument("--port", type=int, default=8042)
    ap.add_argument("--token", default=os.environ.get("TERMUX_BRIDGE_TOKEN", ""))
    args = ap.parse_args()

    WORKSPACE = os.path.realpath(args.workspace)
    TOKEN = args.token or os.environ.get("TERMUX_BRIDGE_TOKEN", "")
    if not TOKEN:
        TOKEN = uuid.uuid4().hex
    os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
    with open(TOKEN_FILE, "w") as f:
        f.write(TOKEN + "\n")
    os.chmod(TOKEN_FILE, 0o644)

    os.makedirs(WORKSPACE, exist_ok=True)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"[bridge] workspace: {WORKSPACE}")
    print(f"[bridge] token file: {TOKEN_FILE}")
    print(f"[bridge] listening on 127.0.0.1:{args.port} (keep Termux alive)")
    srv.serve_forever()


if __name__ == "__main__":
    main()
