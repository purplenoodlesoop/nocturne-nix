{ lib, ... }:
{
  options.services.nocturne.enable = lib.mkEnableOption "Nocturne";
}
