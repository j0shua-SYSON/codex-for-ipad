# Codex GUI feature coverage

CodexPad treats GUI parity as a compatibility contract. For the pinned Codex revision, the catalog contains all **129 client request methods**, all **11 server-to-client request methods**, and all **72 server notifications**.

## How every feature is reachable

- High-frequency workflows have dedicated native controls: threads, turns, interruption, review, files, approvals, user questions, account login, the complete server-provided model catalog, reasoning effort, service tier, collaboration presets, and the Files-to-iSH workspace bridge.
- The Feature Center provides a searchable, categorized native route for every remaining compatible method. It pre-fills active thread and workspace context, accepts structured JSON parameters, shows structured results, confirms destructive requests, and retains the live notification/event stream. This covers experimental and long-tail APIs without requiring the terminal.
- Unknown server requests are shown as answerable JSON request cards instead of silently deadlocking a turn. Known approval and input requests use purpose-built native cards.
- Desktop mode always exposes the complete feature set. Touch mode defaults to the essential workspace; **Settings > Input mode > Show all Codex features** reveals the identical complete Feature Center without changing touch keyboard behavior.

## Pinned surface summary

- 125 user operations are executable in the GUI: 16 purpose-built native routes and 109 Advanced routes.
- `initialize` is automatic and cannot safely be repeated during an active JSON-RPC connection.
- Two Windows sandbox methods are incompatible with iPadOS.
- `mock/experimentalMethod` is an upstream protocol test fixture, not a user feature.

Incoming `account/chatgptAuthTokens/refresh` requests are unavailable because CodexPad uses the local app-server's managed login rather than client-owned external tokens. `attestation/generate` is also unavailable because the pinned protocol expects an opaque client attestation provider that this independent unsigned port cannot issue. Both are surfaced explicitly if requested. Experimental Code Mode remains unavailable because Rusty V8 has no i686-musl distribution; normal turns and tools do not use it.

## Update gate

`scripts/validate-codex-protocol.py` compares the Swift catalog with both the vendored stable JSON schema and the complete Rust protocol macros, including experimental methods filtered from the stable schema. An upstream addition, removal, server request, or notification fails CI until its GUI route and compatibility decision are updated. The weekly Codex update workflow cannot open a pin-update pull request unless this exact-set gate and the full i686/iPadOS build pass.
