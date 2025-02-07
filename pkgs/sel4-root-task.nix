{ seL4-prefix, rustPlatform }:

rustPlatform.buildRustPackage rec {
  name = "hello";
  src = ../.;
  cargoBuildFlags = [ "--package=hello" ];
  cargoRoot = "workspaces/root-task";
  buildAndTestSubdir = cargoRoot;

  doCheck = false;
  SEL4_PREFIX = seL4-prefix;

  cargoLock = {
    lockFile = "${src}/${cargoRoot}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
}
