{ name
, seL4-prefix
, seL4-kernel-loader-add-payload
, seL4-kernel-loader
, task
, runCommand
, which
, lib
}:

runCommand name
{
  meta.mainProgram = "${name}.elf";
  nativeBuildInputs = [
    seL4-kernel-loader-add-payload
    seL4-kernel-loader
    task
    which
  ];
} ''
  mkdir -p $out/bin

  sel4-kernel-loader-add-payload \
    --loader $(which ${lib.getExe seL4-kernel-loader}) \
    --sel4-prefix ${seL4-prefix} \
    --app $(which ${lib.getExe task}) \
    -o $out/bin/${name}.elf
''
