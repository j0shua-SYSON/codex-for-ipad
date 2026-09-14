# Verification record

September 14, 2026 audit and upstream upgrade. This is a development record, not a release certification.

## Confirmed results

- Production Swift model regression executable passed on hosted macOS. It exercises thread isolation, stale responses, draft recovery, duplicate-send prevention, approval decisions, disconnect state and isolated demo responses. The newer run also verifies the bundled schema reference.
- The candidate protocol gate matches 166 client methods, 11 server requests and 84 notifications against upstream `5b1d6560181680f95cde95c14ed042acc02248ed`.
- The i686 compatibility patch applies to the candidate. The former V8 in-process stubs are no longer necessary.
- The candidate cross-compilation and Alpine packaging passed in [run 34824661997](https://github.com/j0shua-SYSON/codex-for-ipad/actions/runs/34824661997). Its original app artifact predates subsequent emulator/UI repairs and must not be treated as the final verified build.
- The 13-inch simulator desktop test passed twice against demo responses. A later run failed its `hasFocus` assertion although the recording showed an insertion cursor and keyboard. The replacement test requires actual application-level typing without another field tap, including after sending, Features dismissal and Terminal recovery; its outcome is pending.
- The mini accessibility/Dark Mode test passed in [run 34828087222](https://github.com/j0shua-SYSON/codex-for-ipad/actions/runs/34828087222). That run also exposed sidebar identifier propagation on the 11-inch simulator. The account control was visible but inherited the container identifier. A containment fix is being tested.
- Real-emulator regression programs pass for MOVMSKPS, CVTDQ2PD, overlapping SIMD shuffles, masked futex wakeups, timeout validation, parent-death signals and clock sleeps.
- Both the old and candidate packaged runtimes complete initialization, `account/read`, `model/list` and `fs/readDirectory` inside the repaired Linux-hosted iSH emulator. The SQLite allocator assertion was caused by aliased SIMD operations overwriting source lanes; it was fixed without bypassing the allocator check.
- Command execution still fails in the unadapted Rust binary: `socketpair(AF_UNIX, SOCK_SEQPACKET)` returns `EINVAL` before fork. The missing parent-death and sleep syscalls have been repaired; the earlier background sleep panic no longer occurs. A version-locked Rust pipe-spawn build is in progress, and the release gate remains closed.

## Fixes under verification

- Thread-local active turns, plans, diffs and drafts; stale resume/directory response protection; paginated history access.
- Failed-send draft recovery, duplicate-start exclusion, late-completion races and correct Stop targeting.
- RPC cancellation, finite ordinary-request deadlines, connection teardown and truthful offline UI.
- Compact-window workbench and pending-request inbox; MCP form/URL acceptance; advertised command decisions.
- Deferred sheet transitions, account-row hit area, adaptive accessibility header, reduced-motion status animation and preserved multiline output.
- Demo preferences and transport no longer touch real saved workspace settings or fail a fake send against a disconnected real RPC client.
- Required-field scaffolding and version-pinned offline JSON parameter reference. Advanced request routing is not equivalent to dedicated forms or end-to-end feature validation.
- Guest socket-pair host-constant translation and descriptor ownership on `EFAULT`/`EMFILE`; a new assembly test covers nonblocking I/O, close-on-exec flags, EOF and cleanup.
- A guest-only Rust 1.95 standard-library patch selects the existing Unix error pipe rather than inventing incorrect packet-socket semantics. Unsupported pidfd requests on this path fail explicitly. Both compiler version and commit must match before applying the patch.

## Evidence boundaries

The iPad UI tests launch `--codexpad-demo`. They verify rendering and input behavior against simulated responses, not authentication, inference, a live Files provider, MCP servers, external integrations or real command execution. Tests now require an actual labelled demo response after sending and exercise the accessibility workbench. Saved screenshots and test bundles must be reviewed, including failures.

The headless iSH probe uses the actual emulator and packaged binary with no model credentials. Linux and Darwin host jobs test instructions, initialization, account/model reads, filesystem reads and harmless Git/ripgrep execution, over stdio and WebSocket. Darwin coverage is newly added and has not yet passed. Even successful probes would not prove physical-iPad performance, foreground/background behavior, provider sign-in, sandbox isolation, hardware keyboard/pointer behavior or App Store distribution.

No physical 13-inch iPad Pro test has been performed during this audit. HIG compliance remains a checklist and verification target, not a certification. Do not advertise this as a finished full local port until the runtime and device checks pass.

## Upstream candidate

The candidate lives on `upgrade/codex-5b1d65601816` until compatibility work is verified. The old pin is `6bd3f5e3db8275c10c7e4bbcc1342c32a89b7eee`; upstream changes include projects, sections, attachments, prompt queues, user verification, Bedrock auth and paginated history. `thread/rollback` was removed in favor of `thread/revert`.

Build/run outcomes are being collected. Failed gates are not waived or described as successful.
