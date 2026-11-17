{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.flake) packages;

  common = {
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

  vm = pkgs.testers.runNixOSTest {
    name = "nocturne";

    nodes = {
      caddy = common;

      traefik = {
        imports = [ common ];
        services.nocturne = {
          proxy = "traefik";
          traefik = {
            entryPoints = [ "web" ];
            tenantSubdomains = true;
          };
        };
        services.traefik = {
          enable = true;
          staticConfigOptions.entryPoints.web.address = ":80";
        };
      };
    };

    testScript = ''
      def check(machine, front):
          machine.wait_for_unit("nocturne-database.service")
          machine.wait_for_unit("nocturne-api.service")
          machine.wait_for_unit("nocturne-web.service")
          machine.wait_for_open_port(5081)
          machine.wait_for_open_port(5082)

          machine.wait_until_succeeds(
              "sudo -u postgres psql -d nocturne -tAc "
              "\"select count(*) from information_schema.tables where table_schema = 'public'\" "
              "| grep -qv '^0$'",
              timeout=300,
          )

          curl = f"curl -s -H 'Host: nocturne.example.org' {front}"

          machine.wait_until_succeeds(f"{curl}/api/v1/status.json | grep -q setup_required", timeout=120)

          api_only = machine.succeed(f"{curl}/openapi/nocturne.json")
          assert "openapi" in api_only or "setup_required" in api_only, api_only[:300]
          assert "<html" not in api_only.lower(), "an API-only path reached the web server"

          machine.fail("ss -tlnH | grep -E ':(5080|5081|5082) ' | grep -v '127.0.0.1'")

      start_all()

      caddy.wait_for_unit("nocturne-gateway.service")
      caddy.wait_for_open_port(5080)
      check(caddy, "http://127.0.0.1:5080")

      traefik.wait_for_unit("traefik.service")
      traefik.fail("systemctl cat nocturne-gateway.service")
      check(traefik, "http://127.0.0.1")

      tenant = traefik.succeed("curl -s -H 'Host: acme.nocturne.example.org' http://127.0.0.1/api/v1/status.json")
      assert "404 page not found" not in tenant, "a tenant subdomain was not routed to Nocturne"
      traefik.succeed(
          "curl -s -H 'Host: deep.acme.nocturne.example.org' http://127.0.0.1/api/v1/status.json "
          "| grep -q '404 page not found'"
      )
      traefik.succeed(
          "curl -s -H 'Host: nocturne.example.org.evil.test' http://127.0.0.1/api/v1/status.json "
          "| grep -q '404 page not found'"
      )
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
