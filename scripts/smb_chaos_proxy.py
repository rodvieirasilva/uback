#!/usr/bin/env python3
"""TCP proxy in front of the local SMB2 test server to simulate slow Wi-Fi and mid-transfer drops."""

from __future__ import annotations

import argparse
import socket
import threading
import time


class ChaosState:
    def __init__(self, drop_after_bytes: int, drop_count: int) -> None:
        self.lock = threading.Lock()
        self.drop_after_bytes = drop_after_bytes
        self.remaining_drops = drop_count
        self.bytes_since_drop = 0

    def should_drop(self, chunk_len: int) -> bool:
        if self.drop_after_bytes <= 0:
            return False
        with self.lock:
            if self.remaining_drops <= 0:
                return False
            self.bytes_since_drop += chunk_len
            if self.bytes_since_drop >= self.drop_after_bytes:
                self.remaining_drops -= 1
                self.bytes_since_drop = 0
                return True
        return False


def pipe(
    src: socket.socket,
    dst: socket.socket,
    delay_sec: float,
    chaos: ChaosState | None,
    label: str,
) -> None:
    try:
        while True:
            data = src.recv(32768)
            if not data:
                break
            if chaos and chaos.should_drop(len(data)):
                print(f"[chaos-proxy] Simulating abrupt disconnect ({label})", flush=True)
                try:
                    src.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                try:
                    dst.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                return
            if delay_sec > 0:
                time.sleep(delay_sec)
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (src, dst):
            try:
                sock.close()
            except OSError:
                pass


def handle_client(
    client_sock: socket.socket,
    target_host: str,
    target_port: int,
    delay_sec: float,
    chaos: ChaosState,
) -> None:
    try:
        upstream = socket.create_connection((target_host, target_port), timeout=10)
    except OSError:
        client_sock.close()
        return

    t1 = threading.Thread(
        target=pipe,
        args=(client_sock, upstream, delay_sec, chaos, "client->smb"),
        daemon=True,
    )
    t2 = threading.Thread(
        target=pipe,
        args=(upstream, client_sock, delay_sec, None, "smb->client"),
        daemon=True,
    )
    t1.start()
    t2.start()


def main() -> int:
    parser = argparse.ArgumentParser(description="Chaos TCP proxy for SMB E2E testing")
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", type=int, required=True)
    parser.add_argument("--delay-ms", type=float, default=0.0, help="Artificial latency per 32KB chunk")
    parser.add_argument(
        "--drop-after-bytes",
        type=int,
        default=0,
        help="Drop TCP socket after forwarding this many client->server bytes (0 = disabled)",
    )
    parser.add_argument("--drop-count", type=int, default=1, help="Number of times to drop socket")
    args = parser.parse_args()

    chaos = ChaosState(args.drop_after_bytes, args.drop_count)
    delay_sec = max(0.0, args.delay_ms / 1000.0)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen_host, args.listen_port))
    server.listen(32)
    print(
        f"[chaos-proxy] Listening on {args.listen_host}:{args.listen_port} -> "
        f"{args.target_host}:{args.target_port} "
        f"(delay={args.delay_ms}ms, drop_after={args.drop_after_bytes}B x{args.drop_count})",
        flush=True,
    )

    while True:
        client_sock, _ = server.accept()
        threading.Thread(
            target=handle_client,
            args=(client_sock, args.target_host, args.target_port, delay_sec, chaos),
            daemon=True,
        ).start()


if __name__ == "__main__":
    raise SystemExit(main())
