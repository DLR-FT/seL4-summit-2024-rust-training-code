{ seL4-prefix
, rustPlatform
, stdenv
, pkgsBuildHost
, target ? "aarch64-sel4"
, package
, buildType ? "release"
, name ? package
, env ? { }
}:

let
  # to use build-std, we need all the dependencies for the rust compiler
  # this fetches all of these dependencies
  compilerDeps =
    rustPlatform.fetchCargoVendor {
      src = "${rustPlatform.rust.rustc}/lib/rustlib/src/rust/library";
      name = "compiler-deps";
      hash = "sha256-xD5HfPSZ29ECNi+26oThxvyLYIBBDe+VU+8RnCjbgtU=";
    };
  # we need to override the cargoBuildHook with the sel4 target
  cargoBuildHook = rustPlatform.cargoBuildHook.overrideAttrs (_: {
    rustHostPlatformSpec = target;
  });
  # because we changed the build target in the cargoBuildHook, we need to change the subdirectory
  # of the cargoInstallHook to the new target aswell
  cargoInstallHook = rustPlatform.cargoInstallHook.overrideAttrs (_: {
    targetSubdirectory = target;
  });
in

rustPlatform.buildRustPackage rec {
  inherit name buildType;
  meta.mainProgram = "${name}.elf";
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
    # we need the bindgenHook from the build host platform, not the target platform
    pkgsBuildHost.rustPlatform.bindgenHook
  ];

  buildInputs = [
    # shadow the old cargoBuildHook and cargoSetupHook with our patched ones
    cargoBuildHook
    cargoInstallHook
  ];

  postPatch = ''
    # Link the compiler dependencies into the cargo-vendor-dir, populated by the cargoSetupHook
    find ${compilerDeps} -mindepth 1 -maxdepth 1 -type d \
      -exec ln -sf {} /build/cargo-vendor-dir/ \;
  '';

  doCheck = false;
  SEL4_PREFIX = seL4-prefix;

  cargoLock = {
    lockFile = "${src}/${cargoRoot}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };

  inherit env;
}
