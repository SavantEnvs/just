//! Ported from the original fork's `src/fuzzing.rs`, which exposed
//! `pub fn compile(text: &str) { let _ = Compiler::test_compile(text); }` from inside
//! the `just` crate. Upstream removed that module and keeps `Compiler` crate-private,
//! so this port drives the identical compilation pipeline (load -> lex -> parse ->
//! analyze, no recipe execution) through the public `just::run()` entry point with
//! `--dump`.

use std::{fs, path::PathBuf, sync::OnceLock};

fn workdir() -> &'static PathBuf {
  static DIR: OnceLock<PathBuf> = OnceLock::new();
  DIR.get_or_init(|| {
    let dir = std::env::temp_dir().join(format!("just-fuzz-{}", std::process::id()));
    fs::create_dir_all(&dir).expect("failed to create fuzz workdir");
    dir
  })
}

pub fn compile(src: &str) {
  let dir = workdir();
  let justfile = dir.join("justfile");
  if fs::write(&justfile, src).is_err() {
    return;
  }
  let _ = just::run(
    [
      "just",
      "--dump",
      "--justfile",
      justfile.to_str().unwrap(),
      "--working-directory",
      dir.to_str().unwrap(),
    ]
    .iter(),
  );
}
