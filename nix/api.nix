{
  lib,
  buildDotnetModule,
  dotnetCorePackages,
  src,
  version,
  alerts,
}:

buildDotnetModule {
  pname = "nocturne-api";
  inherit version src;

  projectFile = "src/API/Nocturne.API/Nocturne.API.csproj";
  nugetDeps = ./api-deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_11_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_11_0;

  postPatch = ''
    rm global.json
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
