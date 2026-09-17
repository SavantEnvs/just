#!/usr/bin/env bash
#
# just/mayhem/build.sh — build casey/just's cargo-fuzz target as a sanitized libFuzzer
# binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS).
#
# just is a pure-Rust command runner. cargo-fuzz drives the build:
#   - it ships its own libFuzzer runtime (the produced binary IS a libFuzzer target — Mayhem
#     runs it directly via `libfuzzer: true`);
#   - ASan is enabled the Rust way, through RUSTFLAGS `-Zsanitizer=address` (NOT clang's
#     $SANITIZER_FLAGS / CFLAGS — those don't apply to rustc). nightly is required.
#
# Targets (mayhem/fuzz/fuzz_targets/*.rs — ported from the old fork's fuzz/ crate):
#   compile — UTF-8-decodes the input, writes it as a justfile and runs `just --dump` over
#             it in-process (load -> lex -> parse -> analyze; no recipe execution).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10). Force DWARF 2 so Mayhem triage / gdb can
# resolve project source lines. The rlenv runtime may export RUST_DEBUG_FLAGS before
# re-running build.sh offline; the default only applies when unset or empty.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# UPSTREAM-commit build fix-up (not a spec-permanent patch): at this commit, Cargo.toml
# requests only nix's "user" feature, but src/signal.rs / src/signals.rs already call
# nix::sys::signal APIs gated behind "signal"/"process"/"fs" — a real gap upstream closed
# later (current master requests ["signal", "user", "fs"]). Patch it at build time so the
# committed source stays untouched. Idempotent (§6.2 item 9): skip if already patched, since
# the PATCH RL tier re-runs build.sh on the same built tree.
if ! grep -q 'features = \["user", "signal", "process", "fs"\]' Cargo.toml; then
  grep -q 'nix = { version = "0.29.0", features = \["user"\] }' Cargo.toml
  sed -i 's/nix = { version = "0.29.0", features = \["user"\] }/nix = { version = "0.29.0", features = ["user", "signal", "process", "fs"] }/' Cargo.toml
fi
grep -q 'features = \["user", "signal", "process", "fs"\]' Cargo.toml

# At this commit, src/fuzzing.rs (behind `#[cfg(fuzzing)] pub mod fuzzing;`, which
# cargo-fuzz activates via --cfg fuzzing) forwards to `testing::compile`, which (a) is itself
# `#[cfg(test)]`-only (fails to build standalone) and (b) unconditionally `.expect()`s a
# successful parse — every syntactically invalid justfile would "crash" the fuzz target on the
# harness's own assertion, not on a real bug in just's code. `Compiler::test_compile` (the
# thing `testing::compile` wraps) is ALSO `#[cfg(test)]`-only at this commit, so it isn't
# reachable from a `--cfg fuzzing` build either. mayhemheroes' own fork fixed exactly this
# (commit c5e5ec7f, "Fix fuzzing harness to not panic on compile errors" + its cfg-gate
# follow-up): widen `test_compile`'s gate to `#[cfg(any(test, fuzzing))]` and have
# `fuzzing::compile` call it directly, discarding the Result instead of `.expect()`-ing it.
# Apply both one-line fixes at build time (idempotent — §6.2 item 9); the mayhem fuzz target
# (mayhem/fuzz/fuzz_targets/compile.rs) reaches this via `just::fuzzing::compile`.
if ! grep -q 'cfg(any(test, fuzzing))' src/compiler.rs; then
  grep -q '#\[cfg(test)\]' src/compiler.rs
  sed -i '0,/#\[cfg(test)\]/s//#[cfg(any(test, fuzzing))]/' src/compiler.rs
fi
grep -q 'cfg(any(test, fuzzing))' src/compiler.rs

# test_compile calls Lexer::test_lex, gated the same way at this commit; same widening.
if ! grep -q 'cfg(any(test, fuzzing))' src/lexer.rs; then
  grep -q '#\[cfg(test)\]' src/lexer.rs
  sed -i '0,/#\[cfg(test)\]/s//#[cfg(any(test, fuzzing))]/' src/lexer.rs
fi
grep -q 'cfg(any(test, fuzzing))' src/lexer.rs

if ! grep -q 'Compiler::test_compile(text)' src/fuzzing.rs; then
  grep -q 'let _ = testing::compile(text);' src/fuzzing.rs
  sed -i 's/let _ = testing::compile(text);/let _ = Compiler::test_compile(text);/' src/fuzzing.rs
fi
grep -q 'Compiler::test_compile(text)' src/fuzzing.rs

# ── DWARF < 4 enforcement ──────────────────────────────────────────────────────────────
# Rust's ASan runtime (librustc-nightly_rt.asan.a) is compiled with the nightly's bundled
# LLVM, which defaults to DWARF 5 and is linked BEFORE the project code. Strip its debug
# sections once so it contributes no DWARF-5 CUs to the final binary.
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 for those CUs.
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

# The cargo-fuzz crate is ADDITIVE under mayhem/fuzz/ (ported from the old fork's fuzz/ —
# upstream ships no fuzz crate; this keeps the overlay purely additive).
FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(compile)
TRIPLE="x86_64-unknown-linux-gnu"

# Replicate OSS-Fuzz `compile` RUSTFLAGS for a libFuzzer+ASan Rust build.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

# LSan-off hook (SPEC.md §6.2 item 15): mayhem/lsan_off.cc is compiled and linked into the
# fuzz binary below by mayhem/fuzz/build.rs (the `cc` crate), since this target's ASan comes
# from RUSTFLAGS rather than $SANITIZER_FLAGS. ASan/UBSan stay fully active; only LeakSanitizer
# is disabled.
echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
done

TARGET_DIR="$(cargo metadata --no-deps --format-version 1 --manifest-path "$FUZZ_DIR/Cargo.toml" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')"
echo "fuzz target_directory: $TARGET_DIR"

REL="$TARGET_DIR/$TRIPLE/release"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$REL/$t"
  if [ ! -x "$bin" ]; then
    echo "ERROR: expected fuzz binary not found at $bin" >&2
    ls -la "$REL" >&2 || true
    exit 1
  fi
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Pre-build the project's TEST suite too — with the crate's NORMAL flags (no sanitizer
# RUSTFLAGS, default target dir) — so mayhem/test.sh only RUNS it, never compiles.
echo "=== cargo test --no-run (normal flags, pre-building the test suite) ==="
RUSTFLAGS="" cargo test --all --tests --no-run --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/compile 2>&1 || true
