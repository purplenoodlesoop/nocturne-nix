{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    core-flake = {
      url = "github:purplenoodlesoop/core-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nocturne-src = {
      url = "github:purplenoodlesoop/nocturne/e0cb3ce803a9ca86612107d1c83ee961d7cc9032";
      flake = false;
    };

    water-ui-src = {
      url = "github:ryceg/water-ui/30918ec89bd1f400a86cc427c95d7679dc2eed4a";
      flake = false;
    };
  };

  outputs =
    {
      core-flake,
      nocturne-src,
      water-ui-src,
      ...
    }:
    with core-flake;
    lib.evalFlake {
      specialArgs = { inherit nocturne-src water-ui-src; };

      config.allowUnfreePredicate = pkg: builtins.elem (pkg.pname or "") [ "water-ui-wasm" ];

      perSystem.imports = with nixosModules; [
        tasks
        ./nix/checks.nix
        ./nix/packages.nix
        ./nix/tasks.nix
      ];

      topLevel.nixosModules = rec {
        nocturne = import ./nixos/module.nix;
        default = nocturne;
      };
    };
}
