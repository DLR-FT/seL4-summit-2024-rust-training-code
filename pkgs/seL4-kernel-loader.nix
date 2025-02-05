{ rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  name = "seL4-kernel-loader";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "seL4";
    repo = "rust-sel4";
    rev = "v${version}";
    hash = "sha256-gZOvuq+icY+6MSlGkPVpqpjzOnhx4G83+x9APc+35nE=";
  };

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
