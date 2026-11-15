{
  lib,
  stdenv,
  rustPlatform,
  cargo,
  rustc,
  lld,
  wasm-bindgen-cli_0_2_128,
  binaryen,
  src,
}:

stdenv.mkDerivation {
  pname = "water-ui-wasm";
  version = builtins.substring 0 8 src.rev;
  inherit src;

  cargoDeps = rustPlatform.importCargoLock { lockFile = "${src}/Cargo.lock"; };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    lld
    wasm-bindgen-cli_0_2_128
    binaryen
  ];

  buildPhase = ''
    runHook preBuild
    export CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_LINKER=lld
    cargo build --offline --profile wasm-release --target wasm32-unknown-unknown -p water-ui-wasm
    wasm-bindgen --target web --out-dir wasm --out-name water_ui \
      target/wasm32-unknown-unknown/wasm-release/water_ui_wasm.wasm
    wasm-opt -Os --enable-bulk-memory --enable-nontrapping-float-to-int \
      -o wasm/water_ui_bg.wasm wasm/water_ui_bg.wasm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r wasm "$out"
    runHook postInstall
  '';

  meta = {
    description = "Watercolour rendering module of water-ui, built for the browser";
    homepage = "https://github.com/ryceg/water-ui";
    license = lib.licenses.unfree;
  };
}
