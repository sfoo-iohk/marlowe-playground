{ inputs, cell }:
let
  inherit (cell.library) pkgs;

  # just the shell scripts
  src = pkgs.lib.cleanSourceWith {
    src = inputs.self;
    filter = with pkgs.lib;
      name: type:
        let baseName = baseNameOf (toString name); in
        (
          (type == "regular" && hasSuffix ".sh" baseName) ||
          (type == "directory")
        );
  };
in
pkgs.runCommand "shellcheck" { buildInputs = [ pkgs.shellcheck ]; } ''
  EXIT_STATUS=0
  cd ${src}
  while IFS= read -r -d ''' i
  do
    if shellcheck -x -e 1008 -e 2148 "$i"
    then
      echo "$i [ PASSED ]"
    else
      echo "$i [ FAILED ]"
      EXIT_STATUS=$(($EXIT_STATUS+1))
    fi
  done <  <(find -name '*.sh' -print0)
  echo $EXIT_STATUS > $out
  echo Total Failed Files: $EXIT_STATUS
  exit "$EXIT_STATUS"
''
