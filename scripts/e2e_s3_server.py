#!/usr/bin/env python3
"""Lightweight local S3-compatible HTTP server for UBack Emulator E2E tests.

Supports:
  - HEAD /<bucket>                  -> 200 OK (bucket existence check)
  - HEAD /<bucket>/<key>            -> 200 OK + Content-Length + x-amz-meta-uback-sha256 (or 404)
  - PUT  /<bucket>/<key>            -> writes object + metadata, returns 200 OK
  - GET  /<bucket>/<key>            -> returns object bytes for full SHA-256 read-back verification
"""

from __future__ import annotations

import argparse
import http.server
import json
import socketserver
from pathlib import Path
from urllib.parse import unquote


class S3Handler(http.server.BaseHTTPRequestHandler):
    root_dir: Path

    def log_message(self, format: str, *args: object) -> None:
        print(f"[s3-e2e] {self.command} {self.path} -> {format % args}", flush=True)

    def _resolve(self) -> tuple[str, Path | None]:
        clean = unquote(self.path.split("?", 1)[0]).strip("/")
        parts = [p for p in clean.split("/") if p]
        if not parts:
            return "", None
        bucket = parts[0]
        if len(parts) == 1:
            return bucket, None
        obj_path = self.root_dir / bucket / Path(*parts[1:])
        return bucket, obj_path

    def do_HEAD(self) -> None:
        bucket, obj_path = self._resolve()
        if not bucket:
            self.send_response(404)
            self.end_headers()
            return
        if obj_path is None:
            (self.root_dir / bucket).mkdir(parents=True, exist_ok=True)
            self.send_response(200)
            self.end_headers()
            return
        if not obj_path.is_file():
            self.send_response(404)
            self.end_headers()
            return
        meta_path = obj_path.with_suffix(obj_path.suffix + ".meta.json")
        self.send_response(200)
        self.send_header("Content-Length", str(obj_path.stat().st_size))
        if meta_path.is_file():
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            for k, v in meta.items():
                self.send_header(k, v)
        self.end_headers()

    def do_PUT(self) -> None:
        bucket, obj_path = self._resolve()
        if not bucket or obj_path is None:
            self.send_response(400)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        obj_path.parent.mkdir(parents=True, exist_ok=True)
        obj_path.write_bytes(data)
        meta = {
            k.lower(): v
            for k, v in self.headers.items()
            if k.lower().startswith("x-amz-meta-")
        }
        meta_path = obj_path.with_suffix(obj_path.suffix + ".meta.json")
        meta_path.write_text(json.dumps(meta), encoding="utf-8")
        self.send_response(200)
        self.end_headers()

    def do_GET(self) -> None:
        bucket, obj_path = self._resolve()
        if not bucket or obj_path is None or not obj_path.is_file():
            self.send_response(404)
            self.end_headers()
            return
        data = obj_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9009)
    parser.add_argument("--dir", required=True)
    args = parser.parse_args()

    root = Path(args.dir)
    root.mkdir(parents=True, exist_ok=True)
    S3Handler.root_dir = root
    with ThreadingTCPServer((args.host, args.port), S3Handler) as httpd:
        print(f"[s3-e2e] Listening on {args.host}:{args.port} (dir={root})", flush=True)
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
