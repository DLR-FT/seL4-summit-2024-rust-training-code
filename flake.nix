{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.fenix = {
    url = "github:nix-community/fenix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.seL4-nix-utils = {
    url = "github:DLR-FT/seL4-nix-utils";
    inputs.flake-utils.follows = "flake-utils";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.rust-sel4 = {
    url = "github:seL4/rust-sel4";
    flake = false; # TODO convince upstream
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , fenix
    , seL4-nix-utils
    , rust-sel4
    ,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ fenix.overlays.default ];
        };
        pkgsCross = import nixpkgs
          {
            inherit system;
            overlays = [ fenix.overlays.default ];
            crossSystem = {
              config = "aarch64-unknown-none-elf";
              rust.rustcTarget = "aarch64-unknown-none";
            };
          };
        pkgsCrossSeL4 = import nixpkgs
          {
            inherit system;
            overlays = [ fenix.overlays.default ];
            crossSystem = {
              config = "aarch64-unknown-none-elf";
              rust.rustcTarget = "aarch64-sel4";
            };
          };

        rust-sel4 = import rust-sel4;

        rust-toolchain = pkgs.fenix.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-GJR7CjFPMh450uP/EUzXeng15vusV3ktq7Cioop945U=";
        };

        seL4-kernel = seL4-nix-utils.packages.${system}.seL4-kernel-arm.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [
            pkgs.pkgsCross.aarch64-embedded.stdenv.cc
            pkgs.qemu_full

            # rust-sel4.worlds.default.sel4-kernel-loader
          ];
          cmakeFlags = [
            "-DCROSS_COMPILER_PREFIX=aarch64-none-elf-"
            "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
            "-DKernelPlatform=qemu-arm-virt"
            "-DKernelArmHypervisorSupport=ON"
            "-DKernelVerificationBuild=OFF"
            "-DARM_CPU=cortex-a53"
          ];
        });
      in
      rec
      {
        packages.seL4-kernel-loader-add-payload =
          (pkgs.callPackage ./pkgs/seL4-kernel-loader.nix {
            rustPlatform = pkgs.makeRustPlatform {
              cargo = rust-toolchain;
              rustc = rust-toolchain;
            };
          }).overrideAttrs
            (old: {
              cargoBuildFlags = "--package=sel4-kernel-loader-add-payload";
            });

        packages.seL4-kernel-loader =
          (pkgsCross.callPackage ./pkgs/seL4-kernel-loader.nix {
            rustPlatform = pkgsCross.makeRustPlatform {
              cargo = rust-toolchain;
              rustc = rust-toolchain;
            };
          }).overrideAttrs
            (old: {
              postPatch = ''
                substituteInPlace crates/sel4-kernel-loader/build.rs --replace-fail "--image-base" "--Ttext"
                substituteInPlace crates/sel4-kernel-loader/build.rs --replace-fail "println!(\"cargo:rustc-link-arg=--no-rosegment\");" ""
              '';
              cargoBuildFlags = [
                "--package=sel4-kernel-loader"
                "--config"
                "target.${pkgsCross.stdenv.targetPlatform.rust.rustcTarget}.linker=\"${pkgsCross.stdenv.cc.targetPrefix}ld\""
              ];
              env.SEL4_PREFIX = seL4-kernel;
            });
        # TODO current this does not build:
        # The reason is that we need the aarch64-sel4 target.
        # For getting the "--target=aarch64-sel4" attached to the cargo build command,
        #   we set the rustcTarget of pkgsCrossSeL4 to "aarch64-sel4".
        # Now the build command uses the target json for aarch64-sel4, but instead of
        #   CC_AARCH64_UNKNOWN_NONE for compiler and linker it sets CC_AARCH64_SEL4 which
        #   results in missing compiler and linker during the build resulting in the error:
        #   "no matching package named `compiler_builtins` found"
        packages.hello-world =
          (pkgsCross.callPackage ./pkgs/sel4-root-task.nix {
            seL4-prefix = seL4-kernel;
            rustPlatform = pkgsCrossSeL4.makeRustPlatform {
              cargo = rust-toolchain;
              rustc = rust-toolchain;
            };
          }).overrideAttrs (old: { });

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.rustPlatform.bindgenHook
            rust-toolchain
            packages.seL4-kernel-loader-add-payload
            packages.seL4-kernel-loader
          ] ++ seL4-nix-utils.devShells.${system}.default.nativeBuildInputs;

          env.SEL4_PREFIX = seL4-kernel;
        };
      }
    );
}
