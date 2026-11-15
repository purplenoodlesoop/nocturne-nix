{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.flake) packages;

  vm = pkgs.testers.runNixOSTest {
    name = "nocturne";

    nodes.machine = {
      imports = [ ../nixos/module.nix ];

      virtualisation = {
        memorySize = 4096;
        cores = 2;
      };

      environment.etc."nocturne.env".text = ''
        INSTANCE_KEY=test-instance-key-0123456789abcdef0123456789
      '';

      services.nocturne = {
        enable = true;
        baseDomain = "nocturne.example.org";
        environmentFile = "/etc/nocturne.env";
        api.package = packages.nocturne-api;
        web.package = packages.nocturne-web;
      };
    };

    testScript = ''
      machine.wait_for_unit("nocturne-database.service")
      machine.wait_for_unit("nocturne-api.service")
      machine.wait_for_unit("nocturne-web.service")
      machine.wait_for_unit("nocturne-gateway.service")
      machine.wait_for_open_port(5081)
      machine.wait_for_open_port(5082)
      machine.wait_for_open_port(5080)

      machine.wait_until_succeeds(
        "sudo -u postgres psql -d nocturne -tAc "
        "\"select count(*) from information_schema.tables where table_schema = 'public'\" "
        "| grep -qv '^0$'",
        timeout=300,
      )

      status = machine.wait_until_succeeds(
        "curl -s -o /dev/null -w '%{http_code}' -H 'Host: nocturne.example.org' "
        "http://127.0.0.1:5080/api/v1/status.json | grep -E '^(200|401|503)$'",
        timeout=120,
      )
      print("legacy status through the gateway:", status)

      machine.succeed(
        "curl -sf -o /dev/null -H 'Host: nocturne.example.org' http://127.0.0.1:5080/openapi/nocturne.json"
        " || curl -s -o /dev/null -w '%{http_code}' -H 'Host: nocturne.example.org'"
        " http://127.0.0.1:5080/ | grep -E '^(200|30[0-9])$'"
      )

      machine.fail("ss -tlnH | grep -E ':(5080|5081|5082) ' | grep -v '127.0.0.1'")
    '';
  };
in
{
  flake.output.checks = {
    inherit (packages)
      nocturne-alerts
      nocturne-api
      nocturne-web
      water-ui-wasm
      ;

    fmt = pkgs.runCommandLocal "nocturne-nix-fmt-check" { } ''
      ${pkgs.nixfmt}/bin/nixfmt --check \
        ${../flake.nix} \
        ${./alerts.nix} \
        ${./api.nix} \
        ${./checks.nix} \
        ${./dotnet-11.nix} \
        ${./packages.nix} \
        ${./tasks.nix} \
        ${./water-ui-wasm.nix} \
        ${./web.nix} \
        ${../nixos/module.nix}
      touch $out
    '';
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux { inherit vm; };
}
