{ inputs, cell }:

let
  inherit (cell.library) writeShellScriptInRepoRoot;

in
writeShellScriptInRepoRoot "assemble-changelog" ''
  usage () {
    echo "$(basename "$0") PACKAGE VERSION
    Assembles the changelog for PACKAGE at VERSION."
  }

  if [ "$#" == "0" ]; then
    usage
    exit 1
  fi

  PACKAGE=$1
  VERSION=$2

  echo "Assembling changelog for $PACKAGE-$VERSION"
  pushd "$PACKAGE" > /dev/null || exit
  scriv collect --version "$VERSION"
  popd > /dev/null || exit
''
