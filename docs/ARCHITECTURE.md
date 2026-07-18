# CodexPad architecture

CodexPad runs the open-source Codex agent and its Linux tool environment locally on iPadOS. Provider-backed model inference remains a network operation. The app combines three layers in one process:

1. **Native workspace** — an adaptive SwiftUI interface for threads, conversation items, plans, approvals, diffs, files, settings, and a recoverable terminal.
2. **Codex app-server** — the upstream Rust `codex-app-server`, cross-compiled as a static 32-bit x86 musl executable. The native client uses the upstream v2 JSON-RPC protocol over an app-local WebSocket.
3. **iSH runtime** — iSH's user-mode x86 emulator, syscall translation, fakefs filesystem, networking, PTYs, and Files integration. It boots a pinned Alpine x86 root containing Codex and essential development tools.

```text
SwiftUI workspace
      |
      | JSON-RPC v2 / ws://127.0.0.1
      v
Codex app-server (i686-musl)
      |
      | Linux syscalls
      v
iSH kernel + x86 emulator -> fakefs -> Files app
```

## Why this boundary

iPadOS does not provide unrestricted process execution or a desktop sandbox API. Porting only the Codex UI would therefore produce a remote client, while compiling Codex directly for arm64-iOS would remove the shell and tool environment that makes it an agent. iSH keeps the complete Linux execution model on-device. The tradeoffs are x86 emulation cost and iPadOS background suspension.

## Pinned sources

- iSH: `997642f3787cc63e65f7134b7bb0362c74bff8e0`
- Codex: `6bd3f5e3db8275c10c7e4bbcc1342c32a89b7eee`
- Rust: `1.95.0`
- Guest target: `i686-unknown-linux-musl`

`Dependencies/upstreams.json` is the single source of truth for these pins. A scheduled workflow discovers new Codex commits, reads their required Rust toolchain, verifies the native client's method and payload contract against that commit's generated JSON Schema, runs the complete i686-musl compatibility build, and opens an update pull request only after those gates pass. Runtime code never assumes a particular Codex version string; protocol capability negotiation and tolerant decoding handle additive v2 changes.

## Runtime contract

- Bind app-server only to guest loopback.
- Complete `initialize` / `initialized` before other requests.
- Delegate credential persistence and refresh to the upstream app-server inside the private iSH root.
- Keep repositories and Codex state inside the selected iSH root.
- Route command, file-change, permission, and user-input requests to native approval surfaces.
- Keep the terminal available as a recovery tool; it is not the primary UI.

## Honest platform limits

- Active turns can be suspended when iPadOS suspends the app.
- Performance depends on x86 emulation and project size.
- External toolchains still need Alpine-compatible x86 packages.
- Experimental Code Mode cannot run in-process because Rusty V8 has no i686-musl distribution. The compatibility layer preserves the upstream service API and returns an explicit error only if that disabled-by-default feature is enabled.
- Provider-backed model inference still requires network access; this architecture does not claim offline LLM inference.
- Distribution must satisfy iSH's GPL terms and the additional iOS permission in `LICENSE.IOS`; Codex notices remain included under Apache-2.0.
