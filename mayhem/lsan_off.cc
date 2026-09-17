// LSan-off hook (SPEC.md §6.2 item 15): disable LeakSanitizer at build time only, for every
// ASan-instrumented target — ASan's memory-corruption checks (and UBSan) stay fully active,
// only leak detection is affected. just's fuzz target gets ASan through rustc's
// `-Zsanitizer=address` (RUSTFLAGS, see build.sh), not clang's $SANITIZER_FLAGS, so this TU is
// compiled and linked into the cargo-fuzz binary via mayhem/fuzz/build.rs (the `cc` crate)
// rather than by build.sh directly.
extern "C" int __lsan_is_turned_off() { return 1; }
