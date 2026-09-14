# Codex i686 compatibility layer

CodexPad builds upstream Codex for iSH's `i686-unknown-linux-musl` guest. The
compatibility patch is intentionally small and applied only in the hosted build
checkout; the sibling/upstream Codex repository is never modified in place.

The latest-upstream candidate uses four target-specific adaptations:

1. builds OpenSSL from source and selects BLAKE3's portable implementation;
2. replaces the unsupported 32-bit seccomp filter with a fail-closed error. CodexPad deliberately
   requests `danger-full-access` only inside the iSH guest, keeps native
   approvals `on-request`, and relies on the iPad application container as the
   operating-system boundary; and
3. selects OpenSSL's built-in lock fallback because Zig's i386 musl runtime
   does not export the `__atomic_is_lock_free` probe used for 64-bit atomics; and
4. rebuilds the guest Rust 1.95 standard library with the existing Unix pipe
   process-launch path. Rust's Linux fork path otherwise requires
   `AF_UNIX/SOCK_SEQPACKET`, which iSH cannot delegate to Darwin. This is not
   emulated with a byte-stream socket: doing so would lose packet semantics.
   The patched fork path explicitly rejects pidfd requests, which iSH cannot
   support. The host compiler and host standard library are unchanged.

`patches/rust-1.95-ish-spawn.patch` applies only to the isolated build's
`rust-src` component. Both Rust 1.95.0 and compiler commit
`59807616e1fa2540724bfbac14d7976d7e4a3860` are required. `RUSTC_BOOTSTRAP=1` is
scoped to the `cargo zigbuild -Z build-std=std,panic_abort` invocation; this uses
an unstable Cargo facility with a pinned compiler, not a floating nightly.
Toolchain upgrades must review this patch and pass the real Linux/Darwin guest
probes before changing the pin. Remove it if iSH implements correct packet
sockets and any required pidfd support, or upstream Rust supplies a suitable
fallback.

Normal Codex app-server operation, tools, approvals, MCP, threads, and turns use
the upstream implementation. Weekly update pull requests must apply this patch,
validate the native protocol contract, cross-compile the app-server, package the
runtime, execute the real guest probes, and build the integrated iPad app before
the pin can advance. These checks do not establish authentication/inference or
physical-device support.

The previous in-process Code Mode substitutions were removed in this update:
upstream moved V8 into a separate host executable, which is not bundled here.

Delete the seccomp fallback if iSH and upstream seccompiler gain a usable 32-bit x86
implementation. Until then, do not describe the guest itself as a security
container: approved tools can access everything exposed in its root.

Delete the OpenSSL compiler guard when the i386 musl linker supplies the atomic
probe or OpenSSL no longer emits it on this target.
