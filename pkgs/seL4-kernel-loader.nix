{ rustPlatform, fetchFromGitHub, rust-sel4 }:

rustPlatform.buildRustPackage rec {
  name = "seL4-kernel-loader";
  version = "1.0.0";

  src = rust-sel4;

  doCheck = false;
  # sourceRoot = "source/crates/sel4-kernel-loader";

  # prePatch = ''
  #   postPatch = "cp ${./Cargo.lock} $sourceRoot/";
  # '';

  cargoLock = {
    lockFile = src + "/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
}
