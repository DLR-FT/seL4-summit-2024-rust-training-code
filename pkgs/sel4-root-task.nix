{ seL4-prefix, rust, cargo, rustPlatform, stdenv, pkgs, pkgsBuildHost, callPackage, makeSetupHook, rustHostPlatformSpec ? "aarch64-sel4", package, buildType ? "release", name ? package }:

let
  compilerDeps =
    rustPlatform.buildRustPackage rec {
      src = "${rustPlatform.rust.rustc}/lib/rustlib/src/rust/library";
      name = "compiler-deps";
      cargoSha256 = "sha256-iN5lfkvpkmFKefrSqmyjSdSgBbOaXdNZ8nfAdHt82Fw=";
      dontBuild = true;
      installPhase = ''
        mkdir $out
        mv /build/compiler-deps-vendor.tar.gz/* $out
      '';
    };
  cargoBuildHook = rustPlatform.cargoBuildHook.overrideAttrs (_: {
    inherit (rust.envVars) setEnv;
    inherit rustHostPlatformSpec;
  });
  cargoInstallHook = rustPlatform.cargoInstallHook.overrideAttrs (_: {
    targetSubdirectory = rustHostPlatformSpec;
  });
in

rustPlatform.buildRustPackage rec {
  inherit name buildType;
  src = ../.;
  cargoBuildFlags = [
    "--package"
    package
    "--config"
    ''target.${stdenv.targetPlatform.rust.rustcTarget}.linker="${stdenv.cc.targetPrefix}ld"''
  ];
  cargoRoot = "workspaces/root-task";
  buildAndTestSubdir = cargoRoot;

  nativeBuildInputs = [
    pkgsBuildHost.rustPlatform.bindgenHook
  ];

  buildInputs = [
    cargoBuildHook
    cargoInstallHook
  ];

  postPatch = ''
    find ${compilerDeps} -mindepth 1 -maxdepth 1 -type d \
      -exec ln -sf {} /build/cargo-vendor-dir/ \;
  '';

  doCheck = false;
  SEL4_PREFIX = seL4-prefix;
  cargoLock = {
    lockFile = "${src}/${cargoRoot}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
}
