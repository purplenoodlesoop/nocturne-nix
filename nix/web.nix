{
  lib,
  stdenv,
  runCommand,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_11,
  nodejs_24,
  makeWrapper,
  src,
  water-ui-src,
  version,
  apiClient,
  waterUiWasm,
}:

let
  webSrc = runCommand "nocturne-web-src-${version}" { } ''
    cp -r ${src}/src/Web "$out"
    chmod -R u+w "$out"
    rm -rf "$out/vendor/water-ui"
    cp -r ${water-ui-src} "$out/vendor/water-ui"
    substituteInPlace "$out/pnpm-workspace.yaml" \
      --replace-fail "enableGlobalVirtualStore: true" "enableGlobalVirtualStore: false"
    substituteInPlace "$out/packages/app/server.js" \
      --replace-fail "server.listen(PORT, () => {" "server.listen(PORT, process.env.HOST, () => {"
    cat >> "$out/pnpm-workspace.yaml" <<'YAML'

    supportedArchitectures:
      os: [linux, darwin]
      cpu: [x64, arm64]
      libc: [glibc]
    YAML
  '';

  workspaces = [ "@nocturne/app..." ];
in

stdenv.mkDerivation (finalAttrs: {
  pname = "nocturne-web";
  inherit version;
  src = webSrc;

  pnpmWorkspaces = workspaces;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    pnpmWorkspaces = workspaces;
    fetcherVersion = 5;
    hash = "sha256-cFG0pt2b7wHIHGQv4pezqRS2Kd8sdeCDomUlSxODh0U=";
  };

  nativeBuildInputs = [
    pnpmConfigHook
    pnpm_11
    nodejs_24
    makeWrapper
  ];

  env = {
    NODE_OPTIONS = "--max-old-space-size=8192";
    PUBLIC_API_URL = "http://localhost:1612";
    PUBLIC_WEBSOCKET_RECONNECT_ATTEMPTS = "5";
    PUBLIC_WEBSOCKET_RECONNECT_DELAY = "1000";
    PUBLIC_WEBSOCKET_MAX_RECONNECT_DELAY = "30000";
    PUBLIC_WEBSOCKET_PING_TIMEOUT = "15000";
    PUBLIC_WEBSOCKET_PING_INTERVAL = "20000";
  };

  buildPhase = ''
    runHook preBuild

    mkdir -p packages/app/src/lib/api/generated vendor/water-ui/packages/water-ui/src/wasm
    cp ${apiClient}/* packages/app/src/lib/api/generated/
    cp ${waterUiWasm}/* vendor/water-ui/packages/water-ui/src/wasm/
    chmod -R u+w packages/app/src/lib/api/generated vendor/water-ui/packages/water-ui/src/wasm

    pnpm run generate-zod-schemas
    pnpm run generate-remote-functions
    pnpm --filter @nocturne/bridge run build
    pnpm --filter @nocturne/bot run build
    pnpm run translations:sync
    pnpm --filter @nocturne/app run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    find . -name node_modules -type d -prune -exec rm -rf {} +
    pnpm install --offline --frozen-lockfile --prod --ignore-scripts --filter "@nocturne/app..."

    app="$out/lib/nocturne-web"
    mkdir -p "$app/packages/app" "$app/packages/bridge"
    cp -r package.json pnpm-workspace.yaml node_modules "$app/"
    cp -r packages/app/{package.json,build,server.js,server-origin-warning.js,node_modules} "$app/packages/app/"
    cp -r packages/bridge/{package.json,dist,node_modules} "$app/packages/bridge/"
    find "$app" -xtype l -print -delete

    makeWrapper ${lib.getExe nodejs_24} "$out/bin/nocturne-web" \
      --add-flags "$out/lib/nocturne-web/packages/app/server.js" \
      --chdir "$out/lib/nocturne-web/packages/app" \
      --set-default NODE_ENV production \
      --set-default BODY_SIZE_LIMIT 44M

    runHook postInstall
  '';

  meta = {
    description = "Nocturne web frontend";
    homepage = "https://github.com/nightscout/nocturne";
    license = lib.licenses.agpl3Only;
    mainProgram = "nocturne-web";
  };
})
