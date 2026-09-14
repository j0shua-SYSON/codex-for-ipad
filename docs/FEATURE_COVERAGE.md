# Codex GUI feature coverage

For candidate `5b1d6560181680f95cde95c14ed042acc02248ed`, the catalog contains all **166 client request methods**, **11 server-to-client request methods**, and **84 server notifications**. Exact-set coverage verifies that no protocol method is silently omitted; it does not prove runtime support or a purpose-built interface for every operation.

## How every feature is reachable

- High-frequency workflows have dedicated native controls: threads, turns, interruption, review, files, approvals, user questions, account login, the complete server-provided model catalog, reasoning effort, service tier, collaboration presets, and the Files-to-iSH workspace bridge.
- The Feature Center provides a searchable, categorized native route for every remaining compatible method. It pre-fills active thread and workspace context, accepts structured JSON parameters, shows structured results, confirms destructive requests, and retains the live notification/event stream. This covers experimental and long-tail APIs without requiring the terminal.
- Unknown server requests are shown as answerable JSON request cards instead of silently deadlocking a turn. Known approval and input requests use purpose-built native cards.
- Desktop mode always exposes the complete feature set. Touch mode defaults to the essential workspace; **Settings > Input mode > Show all Codex features** reveals the identical complete Feature Center without changing touch keyboard behavior.

## Pinned surface summary

- 162 user operations have GUI routes: 16 native routes and 146 Advanced JSON routes. Stable-schema fields and nested definitions are readable offline; experimental requests may require consulting upstream Rust definitions.
- `initialize` is automatic and cannot safely be repeated during an active JSON-RPC connection.
- Two Windows sandbox methods are incompatible with iPadOS.
- `mock/experimentalMethod` is an upstream protocol test fixture, not a user feature.

Incoming `account/chatgptAuthTokens/refresh` requests are unavailable because CodexPad uses the local app-server's managed login rather than client-owned external tokens. `attestation/generate` is also unavailable because this unsigned port has no client attestation provider. Both are surfaced explicitly. Code Mode's separate V8 host is not bundled for i686-musl. See [verification status](VERIFICATION.md) for other unverified runtime dependencies.

## Update gate

`scripts/validate-codex-protocol.py` compares the Swift catalog with both the vendored stable JSON schema and the complete Rust protocol macros, including experimental methods filtered from the stable schema. An upstream addition, removal, server request, or notification fails CI until its GUI route and compatibility decision are updated. The weekly Codex update workflow cannot open a pin-update pull request unless this exact-set gate and the full i686/iPadOS build pass.
