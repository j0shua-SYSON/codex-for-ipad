# Codex i686 compatibility layer

CodexPad builds upstream Codex for iSH's `i686-unknown-linux-musl` guest. The
compatibility patch is intentionally small and applied only in the hosted build
checkout; the sibling/upstream Codex repository is never modified in place.

The layer currently does three target-specific things:

1. builds OpenSSL from source and selects BLAKE3's portable implementation;
2. excludes Rusty V8 on 32-bit musl because upstream publishes no matching V8
   archive; and
3. substitutes a protocol-compatible Code Mode service that returns a clear
   platform error if that experimental, disabled-by-default feature is enabled.

Normal Codex app-server operation, tools, approvals, MCP, threads, and turns use
the upstream implementation. Weekly update pull requests must apply this patch,
validate the native protocol contract, cross-compile the app-server, package the
runtime, and build the integrated iPad app before the pin can advance.

Delete the Code Mode substitution as soon as upstream V8 gains a supported i686
musl artifact or Codex makes that runtime portable to the iSH target.
