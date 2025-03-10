{ inputs, cell }:

# Our nixpkgs comes from haskell-nix and is overlaid with iohk-nix.
# This means that this file is the *only* place where we reference
# `inputs.nixpkgs` directly -- more precisely we reference `inputs.nixpkgs.path`
# because std treats nixpkgs specially, and already `import`s it under the hood.
# This also means that *everywhere else* in nix code we use
# `cell.library.pkgs` to access our overlaid nixpkgs.

let

  pkgs = import inputs.nixpkgs.path {

    config = inputs.haskell-nix.config // {
      # This is required by SASS, which we should move away from!
      permittedInsecurePackages = [ "python-2.7.18.6" ];
    };

    system = inputs.nixpkgs.system;

    overlays = [
      inputs.haskell-nix.overlay
      inputs.iohk-nix.overlays.crypto
    ];

  };

in

pkgs
