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
    args = parser.parse_args()
    process = subprocess.Popen(
        [args.ish, "-f", args.root, "-d", "/root/workspace", "/bin/sh", "-lc",
         "echo CODEXPAD_SHELL_READY >&2; /usr/local/libexec/codexpad/codex-app-server --listen stdio://; result=$?; echo CODEXPAD_SERVER_EXIT=$result >&2; exit $result"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
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
        process.stdin.write(json.dumps(value) + "\n")
        process.stdin.flush()

    def request(identifier, method, params):
        send({"id": identifier, "method": method, "params": params})
        deadline = time.monotonic() + 120
        while True:
            response = messages.get(timeout=max(0.1, deadline - time.monotonic()))
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
        print("PASS: real iSH command execution, Git and ripgrep. Inference/authentication remain untested.", flush=True)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


if __name__ == "__main__":
    main()
