#!/usr/bin/env python3
"""Exercise the real bundled app-server through iSH, without model credentials."""
import argparse
import json
import os
import queue
import signal
import subprocess
import threading
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ish", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--stderr-log")
    parser.add_argument("--transport", choices=["stdio", "websocket"], default="stdio")
    args = parser.parse_args()
    diagnostics = open(args.stderr_log, "w") if args.stderr_log else None
    address = "ws://127.0.0.1:4500" if args.transport == "websocket" else "stdio://"
    connection = None
    stopping = threading.Event()
    process = subprocess.Popen(
        [args.ish, "-f", args.root, "-d", "/root/workspace", "/bin/sh", "-lc",
         f"echo CODEXPAD_SHELL_READY >&2; /usr/local/libexec/codexpad/codex-app-server --listen {address}; result=$?; echo CODEXPAD_SERVER_EXIT=$result >&2; /bin/dmesg >&2; exit $result"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=diagnostics or subprocess.STDOUT,
        text=True, bufsize=1, start_new_session=True,
    )
    messages = queue.Queue()

    def read():
        for line in process.stdout:
            print(line.rstrip(), flush=True)
            try:
                messages.put(json.loads(line))
            except json.JSONDecodeError:
                pass
        messages.put(None)

    threading.Thread(target=read, daemon=True).start()

    def send(value):
        if connection is not None:
            connection.send(json.dumps(value))
        else:
            process.stdin.write(json.dumps(value) + "\n")
            process.stdin.flush()

    def request(identifier, method, params):
        send({"id": identifier, "method": method, "params": params})
        deadline = time.monotonic() + 120
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"No response to {method} within 120 seconds")
            try:
                response = messages.get(timeout=remaining)
            except queue.Empty as error:
                raise TimeoutError(f"No response to {method} within 120 seconds") from error
            if response is None:
                try:
                    status = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    status = "still alive with closed stdout"
                raise RuntimeError(f"iSH app-server exited while awaiting {method}; status={status}")
            if response.get("id") != identifier:
                if "method" in response and "id" in response:
                    raise RuntimeError(f"Unexpected interactive server request: {response['method']}")
                continue
            if "error" in response:
                raise RuntimeError(f"{method}: {response['error']}")
            print(f"PASS: real iSH {method}", flush=True)
            return response["result"]

    try:
        if args.transport == "websocket":
            import websocket
            deadline = time.monotonic() + 120
            while True:
                try:
                    connection = websocket.create_connection(address, timeout=5, suppress_origin=True)
                    connection.settimeout(120)
                    break
                except (OSError, websocket.WebSocketException):
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise
                    time.sleep(0.2)

            def read_socket():
                try:
                    while not stopping.is_set():
                        payload = connection.recv()
                        if not payload:
                            break
                        messages.put(json.loads(payload))
                except (OSError, websocket.WebSocketException, json.JSONDecodeError) as error:
                    if not stopping.is_set():
                        print(f"WebSocket reader failed: {error}", flush=True)
                finally:
                    messages.put(None)

            threading.Thread(target=read_socket, daemon=True).start()
        request(1, "initialize", {"clientInfo": {"name": "codexpad_runtime_probe", "version": "1"},
                                  "capabilities": {"experimentalApi": True}})
        send({"method": "initialized"})
        request(2, "account/read", {"refreshToken": False})
        request(3, "model/list", {"limit": 100, "includeHidden": True})
        request(4, "fs/readDirectory", {"path": "/root/workspace"})
        command = request(5, "command/exec", {
            "command": ["/bin/sh", "-c", "printf codexpad-guest-ok; /usr/bin/git --version; /usr/bin/rg --version"],
            "cwd": "/root/workspace", "timeoutMs": 30000,
            "sandboxPolicy": {"type": "dangerFullAccess"},
        })
        assert command["exitCode"] == 0, command
        assert "codexpad-guest-ok" in command["stdout"], command
        if diagnostics:
            diagnostics.flush()
            with open(args.stderr_log) as log:
                if any("panicked at" in line for line in log):
                    raise RuntimeError("A guest background thread panicked; see the diagnostic log")
        print(f"PASS: real iSH {args.transport} command execution, Git and ripgrep. Inference/authentication remain untested.", flush=True)
    finally:
        stopping.set()
        if connection is not None:
            try:
                connection.close(timeout=1)
            except (OSError, websocket.WebSocketException):
                pass
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        if diagnostics:
            diagnostics.close()


if __name__ == "__main__":
    main()
