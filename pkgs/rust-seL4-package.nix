{ rustPlatform
, rust-sel4
, package
, name ? package
}:

rustPlatform.buildRustPackage rec {
  inherit name;

  src = rust-sel4;

  cargoBuildFlags = [
    "--package=${package}"
  ];

  doCheck = false;

  cargoLock = {
    lockFile = src + "/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
}
