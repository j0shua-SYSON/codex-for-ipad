#!/usr/bin/env python3
"""Fail closed when Codex changes any app-server surface CodexPad must route."""

from __future__ import annotations

import json
import pathlib
import re
import sys


def schema_methods(document: object) -> set[str]:
    methods: set[str] = set()

    def walk(value: object) -> None:
        if isinstance(value, dict):
            properties = value.get("properties")
            if isinstance(properties, dict):
                method = properties.get("method")
                if isinstance(method, dict):
                    enum = method.get("enum")
                    if isinstance(enum, list):
                        methods.update(item for item in enum if isinstance(item, str))
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(document)
    return methods


def read_json(path: pathlib.Path, failures: list[str]) -> object | None:
    if not path.is_file():
        failures.append(f"missing schema: {path.name}")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        failures.append(f"invalid schema {path.name}: {error}")
        return None


def marker_lines(source: str, name: str) -> set[str]:
    begin = f"// CODEXPAD_{name}_BEGIN"
    end = f"// CODEXPAD_{name}_END"
    if begin not in source or end not in source:
        raise ValueError(f"missing {name} marker block")
    block = source.split(begin, 1)[1].split(end, 1)[0]
    return {
        line.strip()
        for line in block.splitlines()
        if line.strip()
        and not line.strip().startswith(("private static", '"""', "//"))
    }


def wire_methods(source: str, start: str, end: str | None) -> set[str]:
    start_index = source.index(start)
    end_index = source.index(end, start_index) if end else len(source)
    return set(re.findall(r'=>\s*"([^"]+)"', source[start_index:end_index]))


def macro_request_methods(source: str, start: str, end: str) -> set[str]:
    start_index = source.index(start)
    end_index = source.index(end, start_index)
    block = source[start_index:end_index]
    methods = set(re.findall(r'=>\s*"([^"]+)"', block))
    for variant in re.findall(r'^\s*([A-Z][A-Za-z0-9_]*)\s*\{', block, re.MULTILINE):
        methods.add(variant[:1].lower() + variant[1:])
    return methods


def compare_exact(
    label: str,
    upstream: set[str],
    catalog: set[str],
    failures: list[str],
) -> None:
    missing = sorted(upstream - catalog)
    stale = sorted(catalog - upstream)
    if missing:
        failures.append(f"{label} missing GUI routes: {', '.join(missing)}")
    if stale:
        failures.append(f"{label} has stale routes: {', '.join(stale)}")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate-codex-protocol.py PATH_TO_SCHEMA_JSON")

    root = pathlib.Path(sys.argv[1]).resolve()
    failures: list[str] = []
    documents: dict[str, object] = {}
    for name in (
        "ClientRequest.json",
        "ServerRequest.json",
        "ServerNotification.json",
        "ClientNotification.json",
    ):
        document = read_json(root / name, failures)
        if document is not None:
            documents[name] = document

    contracts = {
        "ClientRequest.json": {
            "initialize", "thread/list", "thread/start", "thread/resume",
            "thread/archive", "turn/start", "turn/interrupt", "review/start",
            "model/list", "fs/readFile",
            "fs/readDirectory", "account/read", "account/login/start",
            "account/logout", "command/exec",
        },
        "ServerRequest.json": {
            "item/commandExecution/requestApproval",
            "item/fileChange/requestApproval",
            "item/permissions/requestApproval",
            "item/tool/requestUserInput",
            "mcpServer/elicitation/request",
            "item/tool/call",
            "account/chatgptAuthTokens/refresh",
            "attestation/generate",
        },
        "ServerNotification.json": {
            "thread/started", "thread/status/changed", "turn/started",
            "turn/completed", "item/started", "item/completed",
            "item/agentMessage/delta", "item/commandExecution/outputDelta",
            "turn/diff/updated", "turn/plan/updated", "serverRequest/resolved",
            "account/updated", "command/exec/outputDelta",
        },
        "ClientNotification.json": {"initialized"},
        "v2/ThreadStartParams.json": {
            "cwd", "approvalPolicy", "sandbox", "danger-full-access",
            "serviceName", "model", "serviceTier",
        },
        "v2/TurnStartParams.json": {
            "threadId", "clientUserMessageId", "input", "text_elements",
            "model", "effort", "serviceTier",
        },
        "v2/ThreadListParams.json": {
            "cursor", "limit", "sortKey", "recency_at",
        },
        "v2/ModelListParams.json": {"cursor", "limit", "includeHidden"},
        "v2/ModelListResponse.json": {
            "id", "model", "displayName", "description", "hidden",
            "supportedReasoningEfforts", "defaultReasoningEffort",
            "inputModalities", "supportsPersonality", "serviceTiers",
            "defaultServiceTier", "isDefault", "nextCursor",
        },
        "v2/CommandExecParams.json": {
            "command", "sandboxPolicy", "dangerFullAccess", "disableTimeout",
        },
        "ToolRequestUserInputResponse.json": {"answers"},
        "McpServerElicitationRequestResponse.json": {"action", "content", "_meta"},
    }

    checked_tokens = 0
    for relative, expected in contracts.items():
        path = root / relative
        document = documents.get(relative) or read_json(path, failures)
        if document is None:
            continue
        serialized = json.dumps(document, ensure_ascii=False, sort_keys=True)
        missing = sorted(token for token in expected if token not in serialized)
        if missing:
            failures.append(f"{relative} lost: {', '.join(missing)}")
        checked_tokens += len(expected)

    project_root = pathlib.Path(__file__).resolve().parents[1]
    catalog_path = project_root / "app" / "CodexPad" / "CodexFeatureCatalog.swift"
    try:
        catalog_source = catalog_path.read_text(encoding="utf-8")
        catalog_clients = marker_lines(catalog_source, "CLIENT_METHODS")
        catalog_server_requests = marker_lines(catalog_source, "SERVER_REQUESTS")
        catalog_notifications = marker_lines(catalog_source, "SERVER_NOTIFICATIONS")
    except (OSError, ValueError) as error:
        failures.append(f"invalid GUI feature catalog: {error}")
        catalog_clients = set()
        catalog_server_requests = set()
        catalog_notifications = set()

    common_path = root.parents[1] / "src" / "protocol" / "common.rs"
    try:
        common = common_path.read_text(encoding="utf-8")
        stable_clients = schema_methods(documents.get("ClientRequest.json", {}))
        complete_clients = stable_clients | macro_request_methods(
            common, "client_request_definitions! {", "macro_rules! server_request_definitions"
        )
        stable_server_requests = schema_methods(documents.get("ServerRequest.json", {}))
        complete_server_requests = stable_server_requests | macro_request_methods(
            common, "server_request_definitions! {", "server_notification_definitions! {"
        )
        stable_notifications = schema_methods(documents.get("ServerNotification.json", {}))
        complete_notifications = stable_notifications | wire_methods(
            common, "server_notification_definitions! {", "client_notification_definitions! {"
        )
        compare_exact("client methods", complete_clients, catalog_clients, failures)
        compare_exact("server requests", complete_server_requests, catalog_server_requests, failures)
        compare_exact("server notifications", complete_notifications, catalog_notifications, failures)
    except (OSError, ValueError) as error:
        failures.append(f"could not inspect complete Rust protocol: {error}")
        complete_clients = set()
        complete_server_requests = set()
        complete_notifications = set()

    if failures:
        print("CodexPad protocol contract is incompatible:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(
        "CodexPad protocol contract: "
        f"{len(complete_clients)} client methods, "
        f"{len(complete_server_requests)} server requests, "
        f"{len(complete_notifications)} notifications, "
        f"and {checked_tokens} schema tokens GUI-routed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
