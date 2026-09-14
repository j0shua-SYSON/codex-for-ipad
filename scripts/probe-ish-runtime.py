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
    parser.add_argument("--startup", choices=["server", "init"], default="server")
    parser.add_argument("--debugger-lldb", action="store_true")
    args = parser.parse_args()
    if args.startup == "init" and args.transport != "websocket":
        parser.error("init startup requires WebSocket transport")
    if args.debugger_lldb and (args.transport != "websocket" or args.startup != "server"):
        parser.error("LLDB diagnostics require direct WebSocket server startup")
    # Host syscall traces may contain arbitrary guest bytes, not UTF-8 text.
    diagnostics = open(args.stderr_log, "wb") if args.stderr_log else None
    address = "ws://127.0.0.1:4500" if args.transport == "websocket" else "stdio://"
    if args.debugger_lldb:
        # A debugger may leave its inferior alive on failure. Never connect a
        # subsequent diagnostic attempt to the preceding attempt's server.
        import socket
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            address = f"ws://127.0.0.1:{reservation.getsockname()[1]}"
    connection = None
    stopping = threading.Event()
    console_master = console_slave = None
    guest_command = ["/bin/sh", "-lc",
        f"echo CODEXPAD_SHELL_READY >&2; /usr/local/libexec/codexpad/codex-app-server --listen {address}; result=$?; echo CODEXPAD_SERVER_EXIT=$result >&2; /bin/dmesg >&2; exit $result"]
    if args.startup == "init":
        import pty
        console_master, console_slave = pty.openpty()
        guest_command = ["/sbin/init"]
    launch = [args.ish, "-f", args.root, "-d", "/root/workspace", *guest_command]
    if args.debugger_lldb:
        launch = ["lldb", "--batch",
            "-o", "process handle SIGUSR1 -n false -p true -s false",
            "-o", "process handle SIGPIPE -n false -p true -s false",
            "-o", "run", "-k", "thread backtrace all", "-k", "register read",
            "-k", "p current->cpu", "--", *launch]
    process = subprocess.Popen(
        launch,
        stdin=console_slave if console_slave is not None else subprocess.PIPE,
        stdout=console_slave if console_slave is not None else subprocess.PIPE,
        stderr=diagnostics or subprocess.STDOUT,
        # LLDB merges raw syscall bytes into stdout; JSON stdio stays strict.
        text=True, errors="replace" if args.debugger_lldb else "strict",
        bufsize=1, start_new_session=True,
    )
    if console_slave is not None:
        os.close(console_slave)
    output = os.fdopen(console_master, "r", encoding="utf-8", errors="replace") if console_master is not None else process.stdout
    messages = queue.Queue()

    def read():
        try:
            for line in output:
                print(line.rstrip(), flush=True)
                try:
                    messages.put(json.loads(line))
                except json.JSONDecodeError:
                    pass
        except OSError:
            # A PTY master reports EIO when init/the last slave closes.
            if console_master is None:
                raise
        finally:
            messages.put(None)

    output_reader = threading.Thread(target=read, daemon=True)
    output_reader.start()

    def send(value):
        if connection is not None:
            connection.send(json.dumps(value))
        else:
            process.stdin.write(json.dumps(value) + "\n")
            process.stdin.flush()

    def request(identifier, method, params, *, expect_error=False):
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
                if expect_error:
                    print(f"PASS: real iSH {method} reports an error: {response['error']}", flush=True)
                    return response["error"]
                raise RuntimeError(f"{method}: {response['error']}")
            if expect_error:
                raise AssertionError(f"{method} unexpectedly succeeded: {response}")
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
            "command": ["/bin/sh", "-c", "set -e; printf codexpad-guest-ok; /usr/bin/git --version; /usr/bin/rg --version"],
            "cwd": "/root/workspace", "timeoutMs": 30000,
            "sandboxPolicy": {"type": "dangerFullAccess"},
        })
        assert command["exitCode"] == 0, command
        assert "codexpad-guest-ok" in command["stdout"], command
        assert "git version " in command["stdout"], command
        assert "ripgrep " in command["stdout"], command
        nonzero = request(6, "command/exec", {
            "command": ["/bin/sh", "-c", "pwd; printf 'stderr-probe' >&2; exit 7"],
            "cwd": "/root/workspace", "timeoutMs": 30000,
            "sandboxPolicy": {"type": "dangerFullAccess"},
        })
        assert nonzero["exitCode"] == 7, nonzero
        assert nonzero["stdout"].strip() == "/root/workspace", nonzero
        assert nonzero["stderr"] == "stderr-probe", nonzero
        missing = request(7, "command/exec", {
            "command": ["/codexpad-deliberately-missing-executable"],
            "cwd": "/root/workspace", "timeoutMs": 30000,
            "sandboxPolicy": {"type": "dangerFullAccess"},
        }, expect_error=True)
        assert "No such file" in missing["message"] or "os error 2" in missing["message"], missing
        # Exercise fork/exec/exit repeatedly with the real threaded engine.
        # A single successful request is insufficient for lifetime-race checks.
        for identifier in range(8, 28):
            repeated = request(identifier, "command/exec", {
                "command": ["/bin/sh", "-c", "printf repeated-spawn; exit 3"],
                "cwd": "/root/workspace", "timeoutMs": 30000,
                "sandboxPolicy": {"type": "dangerFullAccess"},
            })
            assert repeated["exitCode"] == 3 and repeated["stdout"] == "repeated-spawn", repeated
        if diagnostics:
            diagnostics.flush()
            with open(args.stderr_log, "rb") as log:
                if any(b"panicked at" in line for line in log):
                    raise RuntimeError("A guest background thread panicked; see the diagnostic log")
        print(f"PASS: real iSH {args.transport} ({args.startup} startup) command execution, Git and ripgrep. Inference/authentication remain untested.", flush=True)
    except Exception as error:
        # Retain the reason in the tee'd evidence, not only the hosted job log.
        print(f"FAIL: {type(error).__name__}: {error}", flush=True)
        raise
    finally:
        stopping.set()
        if connection is not None:
            try:
                connection.close(timeout=1)
            except (OSError, websocket.WebSocketException):
                pass
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
        output_reader.join(timeout=2)
        if console_master is not None:
            output.close()
        if diagnostics:
            diagnostics.close()


if __name__ == "__main__":
    main()
