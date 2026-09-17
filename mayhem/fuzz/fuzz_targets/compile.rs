//! Fuzz `just`'s justfile compilation pipeline (lexer -> parser -> analyzer).
//!
//! Upstream ships this exact target at fuzz/fuzz_targets/compile.rs, calling
//! `just::fuzzing::compile(src)` (src/fuzzing.rs, `#[cfg(fuzzing)]`). build.sh applies the
//! mayhemheroes fix (commit c5e5ec7f) to that module at build time so it calls
//! `Compiler::test_compile` directly instead of routing through the `#[cfg(test)]`-only
//! `testing` helper, which isn't compiled outside `cargo test` and unconditionally panics on
//! any parse error (a harness artifact, not a bug in just's code).

#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|src: &str| {
  just::fuzzing::compile(src);
});
