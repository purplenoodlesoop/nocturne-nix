{
  pkgs,
  nocturne-src,
  ...
}:
let
  version = "0.3.2";
  alerts = pkgs.callPackage ./alerts.nix {
    src = nocturne-src;
    inherit version;
  };
in
{
  flake.packages = {
    nocturne-alerts = alerts;
  };
}
