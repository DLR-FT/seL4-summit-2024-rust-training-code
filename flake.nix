{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.fenix = {
    url = "github:nix-community/fenix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.seL4-nix-utils = {
    url = "github:DLR-FT/seL4-nix-utils";
    inputs.flake-utils.follows = "flake-utils";
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

        rust-toolchain = pkgs.fenix.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-GJR7CjFPMh450uP/EUzXeng15vusV3ktq7Cioop945U=";
        };

        rust-sel4-toolchain = pkgs.fenix.fromToolchainFile {
          file = pkgs.concatText "rust-toolchain.tom" [
            "${rust-sel4}/rust-toolchain.toml"
            (pkgs.writeText "rust-toolchain.toml" ''
              targets = ["aarch64-unknown-none"]
            '')
          ];
          sha256 = "sha256-L1F7kAfo8YWrKXHflUaVvCELdvnK2XjcL/lwopFQX2c=";
        };

        seL4RustPlatform = pkgs.makeRustPlatform {
          cargo = rust-sel4-toolchain;
          rustc = rust-sel4-toolchain;
        };

        seL4CrossRustPlatform = pkgsCross.makeRustPlatform {
          cargo = rust-sel4-toolchain;
          rustc = rust-sel4-toolchain;
        };

        crossRustPlatform = pkgsCross.makeRustPlatform {
          cargo = rust-toolchain;
          rustc = rust-toolchain;
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

        tasks = [
          { name = "hello"; }
          { name = "kernel-object"; }
          { name = "address-space"; }
          { name = "serial-device"; }
          { name = "spawn-thread"; }
          { name = "spawn-task"; env.CHILD_ELF = "${self.packages.${system}.tasks.spawn-task-child}/bin/spawn-task-child.elf"; }
          { name = "spawn-task-child"; root = false; }
        ];
      in
      rec
      {

        inherit pkgsCross;
        packages = {
          seL4-generate-target-specs =
            (pkgs.callPackage ./pkgs/rust-seL4-package.nix {
              inherit rust-sel4;
              package = "sel4-generate-target-specs";
              rustPlatform = seL4RustPlatform;
            }).overrideAttrs (old: {
              postFixup = ''
                patchelf --add-rpath \
                  ${(pkgs.lib.makeLibraryPath [ rust-sel4-toolchain ])} \
                  $out/bin/sel4-generate-target-specs
              '';
            });

          seL4-kernel-loader-add-payload =
            (pkgs.callPackage ./pkgs/rust-seL4-package.nix {
              inherit rust-sel4;
              package = "sel4-kernel-loader-add-payload";
              rustPlatform = seL4RustPlatform;
            });

          seL4-kernel-loader =
            (pkgsCross.callPackage ./pkgs/seL4-kernel-loader.nix {
              inherit rust-sel4;
              seL4-prefix = seL4-kernel;
              rustPlatform = seL4CrossRustPlatform;
            });
          foo =
            (pkgsCross.callPackage ./pkgs/sel4-root-task.nix {
              inherit (packages) seL4-kernel-loader-add-payload seL4-kernel-loader;
              name = "foo";
              seL4-prefix = seL4-kernel;
              task = packages.tasks.hello;
            });
          tasks = (builtins.listToAttrs (builtins.map
            ({ name, env ? { }, ... }: {
              inherit name;
              value = (pkgsCross.callPackage ./pkgs/sel4-task.nix {
                inherit env;
                package = name;
                seL4-prefix = seL4-kernel;
                rustPlatform = crossRustPlatform;
              });
            })
            tasks));
          root-tasks = (builtins.listToAttrs (builtins.map
            ({ name, ... }: {
              inherit name;
              value = (pkgsCross.callPackage ./pkgs/sel4-root-task.nix {
                inherit name;
                inherit (packages) seL4-kernel-loader-add-payload seL4-kernel-loader;
                seL4-prefix = seL4-kernel;
                task = packages.tasks.${name};
              });
            })
            (builtins.filter ({ root ? true, ... }: root) tasks)));
        };

        apps = (builtins.listToAttrs (builtins.map
          ({ name, ... }: {
            inherit name;
            value = {
              type = "app";
              program = "${pkgs.lib.getExe (pkgs.writeScriptBin name ''
                #!/usr/bin/env bash
                ${pkgs.lib.getExe' pkgs.qemu_full "qemu-system-aarch64"} \
                  -machine virt,virtualization=on -cpu cortex-a53 -m size=2G \
                  -serial mon:stdio \
                  -nographic \
                  -kernel ${pkgs.lib.getExe packages.root-tasks.${name}}
              '')}";

            };
          })
          (builtins.filter ({ root ? true, ... }: root) tasks)));

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.rustPlatform.bindgenHook
            # rust-toolchain
            rust-sel4-toolchain
            packages.seL4-kernel-loader-add-payload
            packages.seL4-kernel-loader
          ] ++ seL4-nix-utils.devShells.${system}.default.nativeBuildInputs;

          env.SEL4_PREFIX = seL4-kernel;
        };
      }
    );
}
