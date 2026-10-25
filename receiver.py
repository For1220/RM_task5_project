import argparse
import json
import socket
import struct
import threading
import time
from pathlib import Path

import cv2
import numpy as np

HDR = struct.Struct(">4sIQI")
MAGIC = b"RMV1"
MAX_FRAME = 2_000_000


def load_config(path):
    p = Path(path)
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"[CFG] {path}: {exc}; use defaults")
        return {}


def recv_exact(conn, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("disconnected")
        buf.extend(chunk)
    return bytes(buf)


def handle_image(conn, args):
    conn.settimeout(5.0)
    record_dir = Path(args.record) if args.record else None
    if record_dir:
        record_dir.mkdir(parents=True, exist_ok=True)

    started = time.monotonic()
    frames = 0
    gaps = 0
    last_seq = None
    last_report = started

    while True:
        magic, seq, ts_us, size = HDR.unpack(recv_exact(conn, HDR.size))
        if magic != MAGIC or not (0 < size <= MAX_FRAME):
            raise ValueError(f"bad header: magic={magic!r} size={size}")

        jpeg = recv_exact(conn, size)
        t0 = time.perf_counter()
        frame = cv2.imdecode(np.frombuffer(jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)
        decode_ms = (time.perf_counter() - t0) * 1000.0

        if frame is None:
            print(f"[IMAGE] decode failed seq={seq} size={size}")
            continue

        if last_seq is not None and seq != last_seq + 1:
            gaps += max(0, seq - last_seq - 1)
            print(f"[IMAGE] seq gap {last_seq} -> {seq}")
        last_seq = seq
        frames += 1

        now = time.monotonic()
        if now - last_report >= 1.0:
            fps = frames / max(now - started, 1e-6)
            latency_ms = (time.time_ns() // 1000 - ts_us) / 1000.0
            print(
                f"[IMAGE] fps={fps:5.1f} seq={seq} gaps={gaps} "
                f"size={size} decode={decode_ms:.1f}ms latency={latency_ms:.1f}ms"
            )
            last_report = now

        if record_dir and frames % max(1, args.record_every) == 0:
            cv2.imwrite(str(record_dir / f"frame_{seq:08d}.jpg"), frame)

        if not args.headless:
            cv2.imshow("RoboMaster Vision", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                raise KeyboardInterrupt


def handle_state(conn, args):
    conn.settimeout(5.0)
    last_print = 0.0
    for line in conn.makefile("r", encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            state = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"[STATE] bad json: {exc}")
            continue

        if state.get("schema_version") != 1:
            print(f"[STATE] unsupported schema={state.get('schema_version')}")
            continue

        now = time.monotonic()
        if now - last_print >= 1.0:
            print(
                f"[STATE] seq={state.get('seq')} phase={state.get('phase')} "
                f"t={state.get('time_left')} hp={state.get('hp')} "
                f"ammo={state.get('ammo')} entities={len(state.get('entities', []))}"
            )
            last_print = now

        if args.state_log:
            with open(args.state_log, "a", encoding="utf-8") as fp:
                fp.write(line + "\n")


def serve(port, handler, args):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(1)
    print(f"[NET] listening 127.0.0.1:{port}")

    while True:
        conn, addr = srv.accept()
        print(f"[NET] connected {addr} on {port}")
        try:
            handler(conn, args)
        except Exception as exc:
            print(f"[NET] port {port} error: {exc!r}; waiting for reconnect")
        finally:
            conn.close()


def main():
    pre = argparse.ArgumentParser(add_help=False)
    pre.add_argument("--config", default="config/net.json")
    known, _ = pre.parse_known_args()
    cfg = load_config(known.config)

    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=known.config)
    parser.add_argument("--image-port", type=int, default=int(cfg.get("image_port", 9000)))
    parser.add_argument("--state-port", type=int, default=int(cfg.get("state_port", 9001)))
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--record", default="")
    parser.add_argument("--record-every", type=int, default=30)
    parser.add_argument("--state-log", default="")
    args = parser.parse_args()

    threading.Thread(
        target=serve,
        args=(args.state_port, handle_state, args),
        daemon=True,
    ).start()

    serve(args.image_port, handle_image, args)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    finally:
        cv2.destroyAllWindows()