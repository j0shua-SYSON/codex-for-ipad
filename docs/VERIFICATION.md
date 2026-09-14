# Verification record

September 14, 2026 audit and upstream upgrade. This is a development record, not a release certification.

## Confirmed results

- Production Swift model regression executable passed on hosted macOS. It exercises thread isolation, stale responses, draft recovery, duplicate-send prevention, approval decisions, disconnect state and isolated demo responses. The newer run also verifies the bundled schema reference.
- The candidate protocol gate matches 166 client methods, 11 server requests and 84 notifications against upstream `5b1d6560181680f95cde95c14ed042acc02248ed`.
- The i686 compatibility patch applies to the candidate. The former V8 in-process stubs are no longer necessary.
- The candidate cross-compilation and Alpine packaging passed in [run 34824661997](https://github.com/j0shua-SYSON/codex-for-ipad/actions/runs/34824661997). Its original app artifact predates subsequent emulator/UI repairs and must not be treated as the final verified build.
- The 13-inch simulator desktop test passed twice, including a labelled demo response and restored composer focus after sending, Features dismissal, and Terminal recovery. The smaller-layout tests exposed inspector geometry and accessibility identifier problems; fixes are being retested.
- Real-emulator regression programs pass for MOVMSKPS, CVTDQ2PD, overlapping SIMD shuffles, masked futex wakeups and timeout validation.
- The old packaged runtime starts BusyBox and prints Codex help under the real iSH emulator. It does **not** complete initialization. After the shutdown crash and missing instructions were repaired, it reaches a musl allocator assertion during SQLite cleanup (`get_meta`, last-slot index check). Do not bypass this safety check. The candidate runtime is being tested independently.

## Fixes under verification

- Thread-local active turns, plans, diffs and drafts; stale resume/directory response protection; paginated history access.
- Failed-send draft recovery, duplicate-start exclusion, late-completion races and correct Stop targeting.
- RPC cancellation, finite ordinary-request deadlines, connection teardown and truthful offline UI.
- Compact-window workbench and pending-request inbox; MCP form/URL acceptance; advertised command decisions.
- Deferred sheet transitions, account-row hit area, adaptive accessibility header, reduced-motion status animation and preserved multiline output.
- Demo preferences and transport no longer touch real saved workspace settings or fail a fake send against a disconnected real RPC client.
- Required-field scaffolding and version-pinned offline JSON parameter reference. Advanced request routing is not equivalent to dedicated forms or end-to-end feature validation.

## Evidence boundaries

The iPad UI tests launch `--codexpad-demo`. They verify rendering and input behavior against simulated responses, not authentication, inference, a live Files provider, MCP servers, external integrations or real command execution. Tests now require an actual labelled demo response after sending and exercise the accessibility workbench. Saved screenshots and test bundles must be reviewed, including failures.

The headless Linux iSH probe uses the actual emulator and packaged binary with no model credentials. It tests initialization, account/model reads, filesystem reads and a harmless Git/ripgrep command. A passing probe would still not prove physical-iPad performance, foreground/background behavior, provider sign-in, sandbox isolation, hardware keyboard/pointer behavior or App Store distribution.

No physical 13-inch iPad Pro test has been performed during this audit. HIG compliance remains a checklist and verification target, not a certification. Do not advertise this as a finished full local port until the runtime and device checks pass.

## Upstream candidate

The candidate lives on `upgrade/codex-5b1d65601816` until compatibility work is verified. The old pin is `6bd3f5e3db8275c10c7e4bbcc1342c32a89b7eee`; upstream changes include projects, sections, attachments, prompt queues, user verification, Bedrock auth and paginated history. `thread/rollback` was removed in favor of `thread/revert`.

Build/run outcomes are being collected. Failed gates are not waived or described as successful.
