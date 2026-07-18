#!/usr/bin/env python3
"""Fail closed when the pinned app-server schema breaks CodexPad's v2 contract."""

from __future__ import annotations

import json
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate-codex-protocol.py PATH_TO_SCHEMA_JSON")

    root = pathlib.Path(sys.argv[1]).resolve()
    contracts = {
        "ClientRequest.json": {
            "initialize",
            "thread/list",
            "thread/start",
            "thread/resume",
            "thread/archive",
            "turn/start",
            "turn/interrupt",
            "fs/readFile",
            "fs/readDirectory",
            "account/read",
            "account/login/start",
            "account/logout",
        },
        "ServerRequest.json": {
            "item/commandExecution/requestApproval",
            "item/fileChange/requestApproval",
            "item/permissions/requestApproval",
            "item/tool/requestUserInput",
            "mcpServer/elicitation/request",
        },
        "ServerNotification.json": {
            "thread/started",
            "thread/status/changed",
            "turn/started",
            "turn/completed",
            "item/started",
            "item/completed",
            "item/agentMessage/delta",
            "item/commandExecution/outputDelta",
            "turn/diff/updated",
            "turn/plan/updated",
            "serverRequest/resolved",
            "account/updated",
        },
        "v2/ThreadStartParams.json": {
            "cwd",
            "approvalPolicy",
            "sandbox",
            "workspace-write",
            "serviceName",
        },
        "v2/TurnStartParams.json": {
            "threadId",
            "clientUserMessageId",
            "input",
            "text_elements",
        },
        "v2/ThreadListParams.json": {
            "cursor",
            "limit",
            "sortKey",
            "recency_at",
        },
        "ToolRequestUserInputResponse.json": {"answers"},
        "McpServerElicitationRequestResponse.json": {"action", "content", "_meta"},
    }

    failures: list[str] = []
    checked_tokens = 0
    for relative, expected in contracts.items():
        path = root / relative
        if not path.is_file():
            failures.append(f"missing schema: {relative}")
            continue
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            failures.append(f"invalid schema {relative}: {error}")
            continue
        serialized = json.dumps(document, ensure_ascii=False, sort_keys=True)
        missing = sorted(token for token in expected if token not in serialized)
        if missing:
            failures.append(f"{relative} lost: {', '.join(missing)}")
        checked_tokens += len(expected)

    if failures:
        print("CodexPad protocol contract is incompatible:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"CodexPad protocol contract: {checked_tokens} schema tokens verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
