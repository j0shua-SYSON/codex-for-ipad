# CodexPad guest overlay

These files are copied into the pinned Alpine x86 root filesystem by
`scripts/package-runtime-rootfs.sh`. The app-server listens only on guest
loopback and starts through OpenRC. Keep platform-specific changes here rather
than carrying a fork of the Codex Rust workspace.

The package explicitly installs OpenRC. Its inittab keeps the base's gettys,
boot/default runlevels and shutdown, but replaces Linux hardware sysinit with
`usr/local/libexec/codexpad/boot`. iSH has no tmpfs implementation; the adapter
mounts proc only if absent and resets only OpenRC's transient service state
and CodexPad's stale PID file on a fresh init boot. It does not clear projects,
credentials or the rest of `/run`. This follows iSH's service-only boot model:
[upstream OpenRC guidance](https://github.com/ish-app/ish/wiki/How-To-Enable-OpenRC-%26-Start-Services-When-iSH-App-Starts).

Every packaged candidate must pass the `/sbin/init` to WebSocket command probe;
an OpenRC "started" message is not evidence that the engine is reachable.
