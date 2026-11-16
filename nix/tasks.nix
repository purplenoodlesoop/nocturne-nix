{ pkgs, ... }:
let
  files = "flake.nix nix/*.nix nixos/*.nix";
in
{
  tasks = {
    update = {
      description = "Re-pin Nocturne to a tag and refresh water-ui, the NuGet lock and the pnpm hash";
      body = ''
        set -euo pipefail
        cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"

        tag="''${1:-}"
        if [ -z "$tag" ]; then
          echo "usage: nix run .#update -- <tag>   (e.g. v0.3.3)" >&2
          exit 2
        fi

        echo "==> pinning nocturne-src to $tag"
        ${pkgs.gnused}/bin/sed -i "s|github:[^/]*/nocturne/[^\"]*|github:nightscout/nocturne/$tag|" flake.nix
        ${pkgs.nix}/bin/nix flake update nocturne-src

        src=$(${pkgs.nix}/bin/nix eval --raw --impure --expr \
          "(builtins.getFlake (toString ./.)).inputs.nocturne-src.outPath")
        rev=$(${pkgs.curl}/bin/curl -fsS \
          "https://api.github.com/repos/nightscout/nocturne/contents/src/Web/vendor/water-ui?ref=$tag" \
          | ${pkgs.jq}/bin/jq -r .sha)
        echo "==> pinning water-ui-src to $rev"
        ${pkgs.gnused}/bin/sed -i "s|github:ryceg/water-ui/[0-9a-f]*|github:ryceg/water-ui/$rev|" flake.nix
        ${pkgs.nix}/bin/nix flake update water-ui-src
        test -d "$src"

        echo "==> setting version to ''${tag#v}"
        ${pkgs.gnused}/bin/sed -i "s|^  version = \".*\";|  version = \"''${tag#v}\";|" nix/packages.nix

        echo "==> refreshing the NuGet lock"
        ${pkgs.nix}/bin/nix build .#nocturne-api.fetch-deps -o .fetch-deps
        ./.fetch-deps nix/api-deps.json
        rm .fetch-deps

        echo "==> refreshing the pnpm hash"
        ${pkgs.gnused}/bin/sed -i \
          "s|hash = \"sha256-.*\";|hash = \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\";|" nix/web.nix
        got=$(${pkgs.nix}/bin/nix build .#nocturne-web.pnpmDeps --no-link 2>&1 \
          | ${pkgs.gnugrep}/bin/grep -oE 'got: *sha256-[A-Za-z0-9+/=]+' \
          | ${pkgs.gnused}/bin/sed 's/got: *//' | head -1)
        if [ -z "$got" ]; then
          echo "could not determine the pnpm hash" >&2
          exit 1
        fi
        ${pkgs.gnused}/bin/sed -i "s|hash = \"sha256-.*\";|hash = \"$got\";|" nix/web.nix

        echo "==> building everything"
        ${pkgs.nix}/bin/nix build .#nocturne-api .#nocturne-web --no-link
        echo "done - review the diff and commit"
      '';
    };

    fmt = {
      description = "Format every Nix file in the tree";
      body = ''
        set -euo pipefail
        cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
        ${pkgs.nixfmt}/bin/nixfmt ${files}
      '';
    };

    fmt-check = {
      description = "Fail if any Nix file is unformatted";
      body = ''
        set -euo pipefail
        cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
        ${pkgs.nixfmt}/bin/nixfmt --check ${files}
      '';
    };
  };
}
