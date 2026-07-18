/// Controls whether V8 may generate executable code at runtime.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum V8JitMode {
    #[default]
    Enabled,
    Disabled,
}

/// V8 does not publish a library for the 32-bit musl target used by iSH.
pub fn initialize_v8(_jit_mode: V8JitMode) -> Result<(), String> {
    Err("V8 is unavailable on CodexPad's 32-bit iSH runtime".to_string())
}
