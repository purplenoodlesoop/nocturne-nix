{
  pkgs,
  nocturne-src,
  water-ui-src,
  ...
}:
let
  version = "0.3.2";
  alerts = pkgs.callPackage ./alerts.nix {
    src = nocturne-src;
    inherit version;
  };
  waterUiWasm = pkgs.callPackage ./water-ui-wasm.nix { src = water-ui-src; };
in
{
  flake.packages = {
    nocturne-alerts = alerts;
    water-ui-wasm = waterUiWasm;
  };
}
