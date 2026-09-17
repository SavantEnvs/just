// Compiles + links ../lsan_off.cc (the LSan-off hook, SPEC.md §6.2 item 15) into the
// cargo-fuzz binary. `cc` picks up CFLAGS/CXXFLAGS from the environment, so this TU gets the
// same `-gdwarf-3` DWARF override build.sh exports for libfuzzer-sys's own C++ sources.
fn main() {
    println!("cargo:rerun-if-changed=../lsan_off.cc");
    cc::Build::new().file("../lsan_off.cc").cpp(true).compile("lsan_off");
}
