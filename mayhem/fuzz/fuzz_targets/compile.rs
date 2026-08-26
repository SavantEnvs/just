//! Fuzz `just`'s justfile compilation pipeline (lexer -> parser -> analyzer).
//!
//! Ported from the original fork's `fuzz/fuzz_targets/compile.rs`, which called
//! `just::fuzzing::compile(src)`. The `fuzzing` module (also ported, see fuzzing.rs
//! alongside this file) now lives in the fuzz crate itself, since upstream removed
//! `src/fuzzing.rs` and keeps the compiler crate-private.

#![no_main]

mod fuzzing;

use libfuzzer_sys::fuzz_target;

fuzz_target!(|src: &str| {
  fuzzing::compile(src);
});
