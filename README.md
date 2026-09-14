# CodexPad

[![Codex i686 compatibility](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/codex-i686.yml/badge.svg)](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/codex-i686.yml)
[![iSH core CI](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ci.yml/badge.svg)](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ci.yml)
[![iPadOS UI](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ipados-ui.yml/badge.svg)](https://github.com/j0shua-SYSON/codex-for-ipad/actions/workflows/ipados-ui.yml)
[![Public repository](https://img.shields.io/badge/repository-public-0969da)](https://github.com/j0shua-SYSON/codex-for-ipad)

CodexPad is a native iPadOS workspace for the open-source Codex coding agent. It pairs a SwiftUI interface with the real upstream `codex-app-server`, running as a static 32-bit Linux executable inside an embedded iSH/Alpine environment.

> [!IMPORTANT]
> CodexPad is an independent community port, not an official OpenAI or iSH app. It is an actively developed, unsigned preview rather than an App Store release.
>
> Development preview. The latest pinned runtime passes initialization, account/model/filesystem reads, repeated command execution and automatic guest boot on Linux, macOS and memory-sanitized macOS. The native model and three iPad simulator profiles also pass their documented checks. Physical-device performance, provider authentication/inference and live Files-provider integration remain unverified. See [verification status](docs/VERIFICATION.md) before installing or relying on this preview.

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

Choosing a folder in **Settings > Workspace** invokes iSH's native `ios` filesystem driver. The Files picker grants a security-scoped bookmark and iSH mounts that folder at `/root/workspaces/codexpad-files`. CodexPad updates its workspace defaults and requests a thread working-directory update; if the server rejects that update, the thread retains its previous directory. iSH restores saved mounts on later launches. Unlinking requires a live engine and does not delete the folder. Real Files-provider access and relaunch behavior still require device verification.

Folder selection does not silently unmount existing access. Unlink the current folder explicitly before choosing another; cancellation leaves the previous workspace selection unchanged.

## Complete GUI coverage

The searchable Feature Center tracks the exact pinned app-server protocol instead of a hand-picked feature list:

- 166 client request methods, 11 server requests, and 84 notifications are classified and parity-gated for the upgrade candidate.
- 162 user operations have GUI request routes: 16 native routes and 146 Advanced JSON routes. This is routing coverage, not proof that every operation works on iSH.
- Stable operations include an offline parameter-schema reference and required-field scaffolding. Experimental methods omitted by upstream's stable schema link to their pinned protocol definitions.
- Destructive Advanced requests require confirmation and display their structured result and live event stream.
- Three upstream platform/test methods are explicit exceptions; `initialize` is handled automatically.
- Unknown future server requests appear as answerable JSON cards instead of silently deadlocking a turn.

At constrained widths, supporting panes yield to the conversation and remain reachable through native navigation. The compact Feature Center opens its searchable catalog first, then drills into the selected request. See [the exact feature coverage contract](docs/FEATURE_COVERAGE.md).

See [the HIG release checklist](docs/HIG_CHECKLIST.md) and [the architecture](docs/ARCHITECTURE.md) for the design and platform boundaries.

## Build with GitHub Actions

Windows contributors do not need Xcode, Rust, Zig, Docker, or local package installs. Start **Codex i686 compatibility** from the Actions tab or with GitHub CLI:

While this upgrade is unmerged, use `--ref upgrade/codex-5b1d65601816` instead of `--ref main` to test the candidate.

```powershell
gh workflow run codex-i686.yml --repo j0shua-SYSON/codex-for-ipad --ref main
gh run list --repo j0shua-SYSON/codex-for-ipad --workflow codex-i686.yml --limit 1
gh run watch RUN_ID --repo j0shua-SYSON/codex-for-ipad --exit-status
```

The workflow:

1. fetches the exact Codex revision and checks out this reviewed iSH derivative;
2. applies the i686-musl patch and the version-locked guest Rust process-launch patch;
3. proves patched Rust process spawning inside real iSH, then cross-compiles `codex-app-server` with the upstream-pinned Rust toolchain;
4. builds a pinned Alpine x86 image with Git, ripgrep, Python, SSH, and the local OpenRC service;
5. tests emulator instructions and real Codex initialization, model/account reads, filesystem access, and harmless Git/ripgrep execution on Linux and Darwin hosts, over stdio, WebSocket, and automatic OpenRC startup;
6. builds an unsigned arm64 iPadOS app only after the real-runtime gate and native model regressions pass; and
7. uploads the runtime, binary, test evidence, and (on success) `CodexPad-unsigned-iPadOS` artifacts.

For app-only changes, the optional `runtime_artifact_run_id` input reuses a previous runtime artifact. The runtime's exact revision is checked and the real-emulator gate runs again; it does not bypass verification.

For guest package or startup changes, additionally set `repackage_runtime=true`. This extracts and checksum-verifies the previously built binary, then packages it with the current Alpine overlay and repeats all runtime gates. It avoids recompiling Rust when only the root filesystem changes. A non-default binary revision must be supplied explicitly as `codex_revision`.

Every app artifact includes `CodexPadBuild.json`, recording the app commit, source runtime run, runtime SHA-256 and the manifest extracted from that actual runtime. Declared repository pins are recorded separately so testing a candidate override cannot mislabel the embedded binary.

Download the ready-made artifact without a local compile:

```powershell
gh run download RUN_ID --repo j0shua-SYSON/codex-for-ipad --name CodexPad-unsigned-iPadOS
```

Signing and installation require your own Apple development identity. The unsigned artifact is intended for verification and downstream signing; it cannot be installed directly on a stock iPad.

### Existing installations

An app upgrade does **not** overwrite an existing iSH filesystem. On connection,
CodexPad reads the guest's runtime manifest and refuses a Codex revision that
does not match the bundled GUI protocol. It never erases your saved root to make
an update appear successful.

Export a backup of the current filesystem from the terminal's filesystem
settings, then import the new `codexpad-rootfs.tar.gz` as a separate filesystem.
Keep the old filesystem, transfer your projects and `/root/.codex` deliberately,
and select the new filesystem for the next boot. The credential directory is
sensitive; keep its backup private. Verify linked Files folders again after the
switch. Automatic in-place package/data migration is not implemented or claimed
safe; the filesystem-switch and restoration procedure still needs device testing.

For a Mac build, clone with submodules and open `iSH.xcodeproj`. Pass `CODEXPAD_ROOTFS_PATH=/absolute/path/to/codexpad-rootfs.tar.gz` as an Xcode build setting to embed a verified runtime image.

## Clean upstream updates

The current upgrade candidate pins upstream `d77ebc72237a639b6d877f2edc3b20b54631f25e` (the latest `main` snapshot observed on September 14, 2026 at 10:56 UTC), using Rust 1.95.0. It adds project management, queued prompts, attachments, sections, Bedrock setup, user-verification methods, and `thread/revert` in place of `thread/rollback`.

The weekly **Propose Codex update** workflow discovers Codex `main`, reads its Rust toolchain, applies the compatibility patches, and runs the build and real-runtime gates before opening a pin-update pull request. The parity gate compares stable and experimental method names with the GUI catalog and verifies that the bundled stable schema exactly matches upstream. New methods and schema changes require explicit integration work. A Rust version change also requires reviewing the guest standard-library patch; it fails closed on an unreviewed compiler revision. These checks do not replace native regressions or physical-device verification.

Platform-specific code is concentrated in `app/CodexPad`, `runtime`, `patches`, and the build workflows, with small host hooks in `AppGroup.m`, `SceneDelegate.m`, `TerminalViewController`, and the Xcode project. The upstream Codex checkout is never edited in place, and the iSH changes remain deliberately narrow and reviewable.

The small target layer is documented in [`compat/README.md`](compat/README.md). It is deliberately isolated so a future upstream implementation can replace it without forking Codex's application logic.

Rust, Zig and cargo-zigbuild are pinned. Hosted compilation caches are separated by the toolchain and compatibility-patch hashes; source updates can reuse matching dependencies, but the patched-Rust smoke test and complete runtime gates still run. No compiler cache is downloaded to a contributor's C: drive.

## Platform limits

- iPadOS can suspend long-running turns when the app leaves the foreground.
- iSH's x86 emulation is slower than native desktop execution.
- Large toolchains must fit the iPad's storage and be available for Alpine x86.
- Upstream now runs Code Mode through a separate host executable. That V8-based host is not bundled for i686-musl; the obsolete in-process stubs have been removed. Code Mode remains a platform exception.
- iSH is a compatibility environment, not a secure container. Tools can read and modify everything exposed inside the guest root. Approval prompts occur when the configured policy requests them, not necessarily before every command. Do not put secrets in an untrusted workspace.
- The app-server WebSocket transport is currently marked experimental upstream, so every Codex update is compatibility-gated.

## License

This derivative app remains under iSH's GPL terms and its additional iOS distribution permission; see `LICENSE.md` and `LICENSE.IOS`. The bundled Codex executable is Apache-2.0. Exact attribution and source links are in `THIRD_PARTY_NOTICES.md` and are copied into every runtime image.
