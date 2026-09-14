# Codex i686 compatibility layer

CodexPad builds upstream Codex for iSH's `i686-unknown-linux-musl` guest. The
compatibility patch is intentionally small and applied only in the hosted build
checkout; the sibling/upstream Codex repository is never modified in place.

The latest-upstream candidate retains three target-specific adaptations:

1. builds OpenSSL from source and selects BLAKE3's portable implementation;
2. replaces the unsupported 32-bit seccomp filter with a fail-closed error. CodexPad deliberately
   requests `danger-full-access` only inside the iSH guest, keeps native
   approvals `on-request`, and relies on the iPad application container as the
   operating-system boundary; and
3. selects OpenSSL's built-in lock fallback because Zig's i386 musl runtime
   does not export the `__atomic_is_lock_free` probe used for 64-bit atomics.

Normal Codex app-server operation, tools, approvals, MCP, threads, and turns use
the upstream implementation. Weekly update pull requests must apply this patch,
validate the native protocol contract, cross-compile the app-server, package the
runtime, and build the integrated iPad app before the pin can advance.

The previous in-process Code Mode substitutions were removed in this update:
upstream moved V8 into a separate host executable, which is not bundled here.

Delete the seccomp fallback if iSH and upstream seccompiler gain a usable 32-bit x86
implementation. Until then, do not describe the guest itself as a security
container: approved tools can access everything exposed in its root.

Delete the OpenSSL compiler guard when the i386 musl linker supplies the atomic
probe or OpenSSL no longer emits it on this target.
