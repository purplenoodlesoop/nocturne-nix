{
  lib,
  stdenv,
  rustPlatform,
  src,
  version,
}:

rustPlatform.buildRustPackage {
  pname = "nocturne-alerts";
  inherit version src;

  cargoRoot = "crates";
  buildAndTestSubdir = "crates";
  cargoLock.lockFile = "${src}/crates/Cargo.lock";

  cargoBuildFlags = [
    "-p"
    "nocturne-alerts-ffi"
  ];

  cargoTestFlags = [
    "-p"
    "nocturne-alerts-core"
    "-p"
    "nocturne-alerts-ffi"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm444 -t "$out/lib" \
      target/*/release/libnocturne_alerts${stdenv.hostPlatform.extensions.sharedLibrary}
    runHook postInstall
  '';

  meta = {
    description = "Alert rule engine of Nocturne, as a C ABI library";
    homepage = "https://github.com/nightscout/nocturne";
    license = lib.licenses.agpl3Only;
  };
}
