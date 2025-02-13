{ rustPlatform
, stdenv
, rust-sel4
, seL4-prefix
}:

rustPlatform.buildRustPackage rec {
  name = "sel4-kernel-loader";
  meta.mainProgram = name;

  src = rust-sel4;

  cargoBuildFlags = [
    "--package=sel4-kernel-loader"
    "--config"
    "target.${stdenv.targetPlatform.rust.rustcTarget}.linker=\"${stdenv.cc.targetPrefix}ld\""
  ];

  doCheck = false;

  postPatch = ''
    substituteInPlace crates/sel4-kernel-loader/build.rs --replace-fail "--image-base" "--Ttext"
    substituteInPlace crates/sel4-kernel-loader/build.rs --replace-fail "println!(\"cargo:rustc-link-arg=--no-rosegment\");" ""
  '';
  env.SEL4_PREFIX = seL4-prefix;

  cargoLock = {
    lockFile = src + "/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
}
