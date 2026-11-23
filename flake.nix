{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    core-flake = {
      url = "github:purplenoodlesoop/core-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nocturne-src = {
      url = "github:purplenoodlesoop/nocturne/9d7051c9d54f0d36467b68d7f5c6c54cb09c5bc7";
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
