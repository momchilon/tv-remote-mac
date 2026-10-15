"""Loopback-only TLS WebSocket fixture. No third-party dependencies."""
import argparse
import base64
import hashlib
import json
import os
import signal
import socket
import ssl
import struct
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("--directory", required=True)
parser.add_argument("--scenario", default="connect")
args = parser.parse_args()
folder = args.directory
os.makedirs(folder, mode=0o700, exist_ok=True)
cert = os.path.join(folder, "certificate.pem")
key = os.path.join(folder, "key.pem")
if not os.path.exists(cert):
    subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
                    "-out", cert, "-days", "1", "-subj", "/CN=RemoteKit Fixture"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", 8002))
listener.listen(8)
metrics = {"connections": 0, "keyMessages": 0, "pings": 0, "httpRequests": 0, "keys": [], "keyTimes": []}
lock = threading.Lock()

def save():
    with open(os.path.join(folder, "metrics.json.new"), "w") as file:
        json.dump(metrics, file)
    os.replace(os.path.join(folder, "metrics.json.new"), os.path.join(folder, "metrics.json"))

def exact(sock, count):
    result = b""
    while len(result) < count:
        data = sock.recv(count - len(result))
        if not data:
            raise EOFError()
        result += data
    return result

def frame(sock, payload, opcode=1):
    if isinstance(payload, str):
        payload = payload.encode()
    size = len(payload)
    header = bytes([0x80 | opcode])
    header += bytes([size]) if size < 126 else bytes([126]) + struct.pack("!H", size)
    sock.sendall(header + payload)

def handle(raw):
    try:
        with context.wrap_socket(raw, server_side=True) as conn:
            conn.settimeout(10)
            request = b""
            while b"\r\n\r\n" not in request:
                request += exact(conn, 1)
            lines = request.decode().split("\r\n")
            headers = {name.lower(): value.strip() for name, value in (line.split(":", 1) for line in lines[1:] if ":" in line)}
            value = headers["sec-websocket-key"].strip()
            accept = base64.b64encode(hashlib.sha1((value + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
            with lock:
                metrics["connections"] += 1
                save()
            if args.scenario == "delayed":
                time.sleep(0.4)
            if args.scenario != "silent":
                frame(conn, json.dumps({"event": "ms.channel.connect", "data": {"token": "fixture-token"}}))
            while True:
                first, second = exact(conn, 2)
                opcode = first & 0x0f
                size = second & 0x7f
                if size == 126:
                    size = struct.unpack("!H", exact(conn, 2))[0]
                elif size == 127:
                    size = struct.unpack("!Q", exact(conn, 8))[0]
                if size > 65536:
                    return
                mask = exact(conn, 4) if second & 0x80 else None
                body = exact(conn, size)
                if mask:
                    body = bytes(v ^ mask[i % 4] for i, v in enumerate(body))
                if opcode == 8:
                    frame(conn, body, 8)
                    return
                if opcode == 9:
                    with lock:
                        metrics["pings"] += 1
                        save()
                    frame(conn, body, 10)
                elif opcode == 1:
                    message = json.loads(body)
                    if message.get("method") == "ms.remote.control":
                        with lock:
                            metrics["keyMessages"] += 1
                            metrics["keys"].append(message["params"]["DataOfCmd"])
                            metrics["keyTimes"].append(time.monotonic())
                            save()
    except (OSError, EOFError, ValueError, KeyError):
        pass

save()
with open(os.path.join(folder, "ready"), "w") as file:
    file.write("ready")
while True:
    raw, _ = listener.accept()
    threading.Thread(target=handle, args=(raw,), daemon=True).start()
