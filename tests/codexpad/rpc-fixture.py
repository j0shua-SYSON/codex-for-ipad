#!/usr/bin/env python3
"""Bounded loopback-only fixture for the real Swift Foundation RPC client."""
import asyncio
import json
import sys

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed


async def handle(socket):
    answer = None
    try:
        async for payload in socket:
            request = json.loads(payload)
            method = request.get("method")
            if method is None:
                answer = request.get("result")
                continue
            if "id" not in request:
                continue
            identifier = request["id"]
            result = request.get("params") or {}
            if method == "probe/hang":
                continue
            if method == "probe/close":
                await socket.close()
                return
            if method == "probe/error":
                await socket.send(json.dumps({"id": identifier, "error": {"code": -32001, "message": "fixture error"}}))
                continue
            if method == "probe/events":
                await socket.send(json.dumps({"method": "probe/notification", "params": {}}))
                await socket.send(json.dumps({"id": "server-request", "method": "probe/request", "params": {}}))
            if method == "probe/answer":
                result = answer
            if method == "command/exec":
                await asyncio.sleep(35)
                result = {"exitCode": 0, "stdout": "fixture only", "stderr": ""}
            await socket.send(json.dumps({"id": identifier, "result": result}))
    except ConnectionClosed:
        pass


async def main():
    async with serve(handle, "127.0.0.1", 0, ping_interval=None) as server:
        port = server.sockets[0].getsockname()[1]
        process = await asyncio.create_subprocess_exec(sys.argv[1], f"ws://127.0.0.1:{port}")
        try:
            status = await asyncio.wait_for(process.wait(), timeout=180)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()
            raise
    return status


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
