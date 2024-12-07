{
  inputs.call-flake.url = github:divnix/call-flake;
  outputs = inputs: {
     # Patch underlying flake source tree
    # NOTE Adapted from https://discourse.nixos.org/t/apply-a-patch-to-an-input-flake/36904
    lib.patchFlake = {
      flake,
      pkgs,
      patches,
      lockFileEntries ? {},
    }: let
      inherit (pkgs) applyPatches fetchpatch2 lib nix;
      inherit (lib) forEach isAttrs getExe pathExists importJSON mergeAttrs generators fileContents;
      ifElse = condition: yes: no: if condition then yes else no;

      # Patched flake source
      patched =
        (applyPatches {
          name = "flake";
          src = flake;
          patches = forEach patches (patch:
            if isAttrs patch
            then fetchpatch2 patch
            else patch);
        })
        .overrideAttrs (_: old: {
          outputs = ["out" "narHash"];
          installPhase = ''
            ${old.installPhase}
            ${getExe nix} \
              --extra-experimental-features nix-command \
              --offline \
              hash path ./ \
              > $narHash
          '';
        });

      # New lock file
      lockFile = let
        lockFilePath = "${patched.outPath}/flake.lock";
        lockFileExists = pathExists lockFilePath;
        original = importJSON lockFilePath;
        root = ifElse lockFileExists original.root "root";
        nodes = ifElse lockFileExists (mergeAttrs original.nodes lockFileEntries) {root = {};};
      in
        builtins.unsafeDiscardStringContext (generators.toJSON {} {inherit root nodes;});

      # New flake object
      flake = {
        inherit (patched) outPath;
        narHash = fileContents patched.narHash;
      };
    in
      (import "${inputs.call-flake}/call-flake.nix") lockFile flake "";

    lib.patchPkgs = pkgs: patches: let
      patched-nixpkgs = pkgs.applyPatches {
        inherit patches;
        src = pkgs.path;
      };
    in import patched-nixpkgs {inherit (pkgs) system;};
  };
}
