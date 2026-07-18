# CodexPad

[![Codex i686 compatibility](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/codex-i686.yml/badge.svg)](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/codex-i686.yml)
[![iSH core CI](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ci.yml/badge.svg)](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ci.yml)
[![iPadOS UI](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ipados-ui.yml/badge.svg)](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ipados-ui.yml)
[![Public repository](https://img.shields.io/badge/repository-public-0969da)](https://github.com/j0shua-SYSON/codex-for-ipad)

CodexPad is a native iPadOS workspace for the open-source Codex coding agent. It pairs a SwiftUI interface with the real upstream `codex-app-server`, running as a static 32-bit Linux executable inside an embedded iSH/Alpine environment.

> [!IMPORTANT]
> CodexPad is an independent community port, not an official OpenAI or iSH app. It is an actively developed, unsigned preview rather than an App Store release.

## What runs locally

- Codex agent orchestration, shell commands, Git, patches, and workspace files run on the iPad.
- The native UI talks to the guest only through `ws://127.0.0.1:4500`.
- The iSH terminal remains available as a recovery and advanced-work surface.
- Agent threads use Codex's `danger-full-access` mode inside the private iSH guest because iSH cannot enforce the desktop Linux seccomp/namespace sandbox. Native command and file-change approvals remain `on-request`; the iPad app container is the outer operating-system boundary.
- Model inference still uses the provider configured in Codex and therefore normally requires network access. CodexPad is not claiming offline on-device LLM inference.

## iPad support

CodexPad targets iPad only and requires iPadOS 17 or later. The adaptive layout supports the 13-inch iPad Pro; hosted UI gates explicitly exercise 13-inch and 11-inch iPad Pro simulators at standard text size and an iPad mini at an accessibility text size in Dark Mode. A physical-device accessibility and distribution pass is still required before a release.

## Touch and desktop modes

| Capability | Touch mode | Desktop mode |
| --- | --- | --- |
| Primary input | Direct touch and software keyboard | Pointer, trackpad, and hardware keyboard |
| Default density | Essential workspace controls | Complete compatible Codex surface |
| Complete Feature Center | Optional with **Show all Codex features** | Always available |
| Composer focus | Dismisses naturally while scrolling or sending | Restored after the first click across send, stop, navigation, sheets, and terminal recovery |
| Launch behavior | Never opens the software keyboard automatically | Never steals focus until the composer is first engaged |

Turning on **Show all Codex features** does not switch touch mode into desktop behavior. It reveals the same complete controls while preserving touch-oriented keyboard and scrolling behavior.

## Native workspace and Files bridge

The interface uses a native `NavigationSplitView` for recent threads and the semantic activity timeline, plus a workbench inspector for plans, diffs, files, and runtime diagnostics. It includes native command/file/permission approvals, `request_user_input`, account sign-in, review controls, keyboard shortcuts, pointer-friendly system controls, Dynamic Type, VoiceOver labels, dark mode, and compact-width adaptation. The model picker is populated by paginating upstream `model/list`, including provider-hidden entries, supported reasoning efforts, service tiers, modalities, and collaboration presets instead of hard-coding model names.

Choosing a folder in **Settings > Workspace** invokes iSH's native `ios` filesystem driver. The Files picker grants a security-scoped bookmark, iSH mounts that folder at `/root/workspaces/codexpad-files`, and CodexPad immediately uses the guest mount as the thread working directory. The native Files panel and request defaults recognize the linked workspace, and iSH restores the mount on later launches. Unlinking removes only saved access and the mount; it does not delete the folder.

## Complete GUI coverage

The searchable Feature Center tracks the exact pinned app-server protocol instead of a hand-picked feature list:

- 129 client request methods, 11 server requests, and 72 notifications are classified and parity-gated.
- 125 user operations are executable in the GUI: 16 purpose-built native routes and 109 structured Advanced routes.
- Destructive Advanced requests require confirmation and display their structured result and live event stream.
- Three upstream platform/test methods are explicit exceptions; `initialize` is handled automatically.
- Unknown future server requests appear as answerable JSON cards instead of silently deadlocking a turn.

At constrained widths, supporting panes yield to the conversation and remain reachable through native navigation. The compact Feature Center opens its searchable catalog first, then drills into the selected request. See [the exact feature coverage contract](docs/FEATURE_COVERAGE.md).

See [the HIG release checklist](docs/HIG_CHECKLIST.md) and [the architecture](docs/ARCHITECTURE.md) for the design and platform boundaries.

## Build with GitHub Actions

Windows contributors do not need Xcode, Rust, Zig, Docker, or local package installs. Start **Codex i686 compatibility** from the Actions tab or with GitHub CLI:

```powershell
gh workflow run codex-i686.yml --repo j0shua-SYSON/codex-for-ipad --ref main
gh run list --repo j0shua-SYSON/codex-for-ipad --workflow codex-i686.yml --limit 1
gh run watch RUN_ID --repo j0shua-SYSON/codex-for-ipad --exit-status
```

The workflow:

1. fetches the exact Codex and iSH revisions in `Dependencies/upstreams.json`;
2. applies the small i686-musl compatibility patch;
3. cross-compiles `codex-app-server` with the upstream-pinned Rust toolchain;
4. builds a pinned Alpine x86 image with Git, ripgrep, Python, SSH, and the local OpenRC service;
5. builds an unsigned arm64 iPadOS app containing that verified image; and
6. uploads `CodexPad-unsigned-iPadOS`, `codexpad-runtime-i686`, and `codex-app-server-i686-musl` artifacts.

Download the ready-made artifact without a local compile:

```powershell
gh run download RUN_ID --repo j0shua-SYSON/codex-for-ipad --name CodexPad-unsigned-iPadOS
```

Signing and installation require your own Apple development identity. The unsigned artifact is intended for verification and downstream signing; it cannot be installed directly on a stock iPad.

For a Mac build, clone with submodules and open `iSH.xcodeproj`. Pass `CODEXPAD_ROOTFS_PATH=/absolute/path/to/codexpad-rootfs.tar.gz` as an Xcode build setting to embed a verified runtime image.

## Clean upstream updates

The weekly **Propose Codex update** workflow discovers Codex `main`, reads its Rust toolchain, applies the compatibility patch, builds the complete i686 runtime and iPad app, and only then opens a pin-update pull request. The parity gate compares all stable and experimental client methods, server requests, and notifications with the GUI catalog; a new operation cannot merge until it has a deliberate native, Advanced, automatic, or incompatible route. Additive payload fields are decoded tolerantly, while breaking schema or target changes fail instead of silently shipping a partial port.

Platform-specific code is concentrated in `app/CodexPad`, `runtime`, `patches`, and the build workflows, with small host hooks in `AppGroup.m`, `SceneDelegate.m`, `TerminalViewController`, and the Xcode project. The upstream Codex checkout is never edited in place, and the iSH changes remain deliberately narrow and reviewable.

The small target layer is documented in [`compat/README.md`](compat/README.md). It is deliberately isolated so a future upstream implementation can replace it without forking Codex's application logic.

## Platform limits

- iPadOS can suspend long-running turns when the app leaves the foreground.
- iSH's x86 emulation is slower than native desktop execution.
- Large toolchains must fit the iPad's storage and be available for Alpine x86.
- Experimental Code Mode is disabled by default upstream and reports a clear platform error on CodexPad because Rusty V8 has no published i686-musl library. Normal app-server tools and agent turns do not use this subsystem.
- iSH is a compatibility environment, not a secure container. Codex tools can read and modify everything exposed inside the selected guest root after approval; do not place untrusted secrets in that root.
- The app-server WebSocket transport is currently marked experimental upstream, so every Codex update is compatibility-gated.

## License

This derivative app remains under iSH's GPL terms and its additional iOS distribution permission; see `LICENSE.md` and `LICENSE.IOS`. The bundled Codex executable is Apache-2.0. Exact attribution and source links are in `THIRD_PARTY_NOTICES.md` and are copied into every runtime image.
