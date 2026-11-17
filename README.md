# nocturne-nix

Nix packaging and a NixOS module for [Nocturne](https://github.com/nightscout/nocturne), the
Nightscout-compatible diabetes data platform. Everything is built from source; no container
images are involved.

## Source

Nocturne v0.3.2 plus six changes, each exactly as submitted upstream, from
[purplenoodlesoop/nocturne `deploy/v0.3.2`](https://github.com/purplenoodlesoop/nocturne/tree/deploy/v0.3.2):

- v3 settings writes are announced on the `settings` storage socket, which AAPS 4.0 client
  control needs ([nightscout/nocturne#3454](https://github.com/nightscout/nocturne/pull/3454)).
- AAPS 4.0 uploads are recognised as AAPS rather than OpenAPS
  ([nightscout/nocturne#3467](https://github.com/nightscout/nocturne/pull/3467)).
- The loop and IOB pill times follow the 12/24-hour preference
  ([nightscout/nocturne#3468](https://github.com/nightscout/nocturne/pull/3468)).
- An AAPS phone's loop status is listed as an AndroidAPS data source rather than OpenAPS
  (the first commit of [nightscout/nocturne#3469](https://github.com/nightscout/nocturne/pull/3469);
  its second commit covers a connections list v0.3.2 does not have).
- A status-rail pill for the link battery voltage AndroidAPS reports for an OrangeLink
  ([nightscout/nocturne#3470](https://github.com/nightscout/nocturne/pull/3470), with
  [nightscout/AndroidAPS#5594](https://github.com/nightscout/AndroidAPS/pull/5594) on the phone).
- The dashboard's prediction curves refresh when a newer reading arrives instead of keeping
  the forecast from page load ([nightscout/nocturne#3497](https://github.com/nightscout/nocturne/pull/3497)).

The reported version stays 0.3.2. `nix run .#update -- <tag>` returns to an upstream tag once a
release carries the fixes.

## What gets built

| Output | From | With |
|---|---|---|
| `nocturne-alerts` | `crates/` | Rust, the alert engine as a C ABI library |
| `water-ui-wasm` | the `water-ui` submodule | Rust to wasm32, `wasm-bindgen` 0.2.128, `wasm-opt` |
| `nocturne-api` | `src/API` | .NET 11, NuGet locked in `nix/api-deps.json` |
| `nocturne-api.client` | the built API | NSwag: the OpenAPI document and the TypeScript client the web build reads |
| `nocturne-web` | `src/Web` | pnpm 11, Node 24, SvelteKit with adapter-node |

The API loads `nocturne-alerts` from its own output, so the build never downloads the prebuilt
library upstream's project would otherwise fetch.

The web build asks Node for an 8 GB heap. Build on a machine with at least 12 GB of memory and
copy the closure to a smaller server.

`water-ui` is published without a licence ("all rights reserved") by Nocturne's maintainer and is
bundled into Nocturne's own images. It is marked unfree here and allowed by name for this flake's
package set only.

nixpkgs carries only a .NET 11 release candidate at the moment, so `nix/dotnet-11.nix` pins the
final 11.0.0 runtime and 11.0.100 SDK. It is generated from Microsoft's release metadata by
nixpkgs' own `dotnetCorePackages.generate-dotnet-sdk` and loaded with `buildDotnetSdk`; drop it
once nixpkgs has the release.

## The module

```nix
{
  imports = [ inputs.nocturne-nix.nixosModules.default ];

  services.nocturne = {
    enable = true;
    baseDomain = "nocturne.example.org";
    environmentFile = "/run/secrets/nocturne.env";
    api.package = inputs.nocturne-nix.packages.${pkgs.system}.nocturne-api;
    web.package = inputs.nocturne-nix.packages.${pkgs.system}.nocturne-web;
  };
}
```

`environmentFile` must set `INSTANCE_KEY` (at least 32 characters). It signs tokens and encrypts
the secrets Nocturne stores, so keep a copy off the server.

What the module runs:

- **PostgreSQL 17** with the database and Nocturne's three roles (`nocturne_migrator` owns the
  schema and runs migrations, `nocturne_app` is the runtime role, `nocturne_web` holds bot state).
  The services connect over the Unix socket with peer authentication, so there is no database
  password at all.
- **`nocturne-api`** and **`nocturne-web`**, each on a loopback port, as systemd services with
  `DynamicUser` and the usual hardening.
- The request split upstream's gateway does: a handful of authentication and API documentation
  paths go to the API, everything else to the web server, which proxies the rest of `/api`
  itself. With `proxy = "caddy"` (the default) a loopback Caddy, `nocturne-gateway`, does it on
  `services.nocturne.port`; point any TLS-terminating reverse proxy there and add its address
  to `trustedProxies` if it is not on loopback. With `proxy = "traefik"` the module instead adds
  two routers and two services for `baseDomain` to the host's `services.traefik`, from the same
  route list, and no gateway runs:

  ```nix
  services.nocturne = {
    proxy = "traefik";
    traefik = {
      entryPoints = [ "websecure" ];
      certResolver = "letsencrypt";
    };
  };
  ```

A single-tenant install answers on `baseDomain` itself, but Nocturne still hands out its
tenant's subdomain, `<slug>.<baseDomain>`: in uploader setup links, and as the place it relays
OIDC account-linking and connector callbacks to. `traefik.tenantSubdomains = true` routes those
subdomains too and asks `certResolver` for a certificate covering `*.<baseDomain>`, which needs a
DNS-01 challenge and a wildcard DNS record pointing at the host.

## Tasks

```
nix run .#update -- v0.3.3   # move the pin, water-ui, the NuGet lock and the pnpm hash together
nix run .#fmt
nix flake check              # builds everything; on Linux also boots the module in a VM
```

## Licence

The packaging is MIT. Nocturne is AGPL-3.0 and is fetched at build time, not vendored.
