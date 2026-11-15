{
  lib,
  buildDotnetModule,
  jq,
  dotnetCorePackages,
  src,
  version,
  alerts,
}:

let
  dotnet = dotnetCorePackages.buildDotnetSdk ./dotnet-11.nix;
in

buildDotnetModule {
  pname = "nocturne-api";
  inherit version src;

  projectFile = "src/API/Nocturne.API/Nocturne.API.csproj";
  nugetDeps = ./api-deps.json;

  dotnet-sdk = dotnet.sdk_11_0;
  dotnet-runtime = dotnet.aspnetcore_11_0;

  postPatch = ''
    substituteInPlace src/API/Nocturne.API/Nocturne.API.csproj \
      --replace-fail \
        'RemoveProperties="TargetFramework;RuntimeIdentifier;SelfContained;PublishDir;PublishProfile;_IsPublishing">' \
        'RemoveProperties="TargetFramework;RuntimeIdentifier;SelfContained;PublishDir;PublishProfile;_IsPublishing;NoBuild">'
  '';

  dotnetFlags = [
    "-p:GenerateNSwagClient=false"
    "-p:Version=${version}"
    "-p:NocturneAlertsNativeDir=${alerts}/lib/"
  ];

  dotnetInstallFlags = [ "-p:PublishReadyToRun=false" ];

  nativeBuildInputs = [ jq ];

  outputs = [
    "out"
    "client"
  ];

  postBuild = ''
    pushd src/API/Nocturne.API
    nswag=$(dotnet msbuild -getProperty:NSwagExe_Net100 -p:Configuration=Release)
    rid=$(basename bin/Release/net11.0/*/)
    jq --arg rid "$rid" '.documentGenerator.aspNetCoreToOpenApi.runtime = $rid' nswag.json > nswag.rid.json
    eval env DOTNET_ROLL_FORWARD=Major \
      "'ConnectionStrings__nocturne-postgres=Host=localhost'" \
      "'ConnectionStrings__nocturne-postgres-migrator=Host=localhost'" \
      "$nswag" run nswag.rid.json /variables:Configuration=Release
    popd
  '';

  postInstall = ''
    cp -r src/Web/packages/app/src/lib/api/generated "$client"
  '';

  executables = [ "Nocturne.API" ];

  makeWrapperArgs = [
    "--set-default"
    "NOCTURNE_ALERTS_NATIVE_DIR"
    "${alerts}/lib"
  ];

  meta = {
    description = "Nightscout-compatible diabetes data API";
    homepage = "https://github.com/nightscout/nocturne";
    license = lib.licenses.agpl3Only;
    mainProgram = "Nocturne.API";
  };
}
