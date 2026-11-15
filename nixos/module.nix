{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;

  cfg = config.services.nocturne;

  settingsType = types.attrsOf (
    types.oneOf [
      types.str
      types.int
      types.bool
    ]
  );

  render = value: if builtins.isBool value then lib.boolToString value else toString value;

  loopback = port: "http://127.0.0.1:${toString port}";

  socket = "/run/postgresql";

  npgsql = role: "Host=${socket};Database=${cfg.database.name};Username=${role}";

  apiRoutes = [
    "/api/auth/oidc/*"
    "/api/oauth/*"
    "/api/v4/dev-only/*"
    "/api/auth/platform-access"
    "/api/auth/platform-access/*"
    "/scalar"
    "/scalar/*"
    "/openapi/*"
    "/.well-known/*"
    "/pebble"
  ];

  caddyfile = pkgs.writeText "nocturne-gateway.Caddyfile" ''
    {
      admin off
      auto_https off
      persist_config off
      servers {
        trusted_proxies static ${lib.concatStringsSep " " cfg.trustedProxies}
      }
    }

    http://:${toString cfg.port} {
      bind ${cfg.address}
      @api path ${lib.concatStringsSep " " apiRoutes}
      reverse_proxy @api ${loopback cfg.api.port}
      reverse_proxy ${loopback cfg.web.port}
    }
  '';

  hardening = {
    DynamicUser = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    NoNewPrivileges = true;
    SystemCallArchitectures = "native";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    Restart = "on-failure";
    RestartSec = 5;
  };

  databaseUnits = lib.optionals cfg.database.createLocally [
    "postgresql.service"
    "nocturne-database.service"
  ];
in
{
  options.services.nocturne = {
    enable = mkEnableOption "Nocturne, a Nightscout-compatible diabetes data platform";

    baseDomain = mkOption {
      type = types.str;
      description = ''
        The public hostname Nocturne is served on, without scheme. A single-tenant
        install answers on this name itself; further tenants would live on its
        subdomains.
      '';
      example = "nocturne.example.org";
    };

    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Address the gateway binds. Loopback by default; put a TLS-terminating
        reverse proxy in front of it.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 5080;
      description = "Port of the gateway, the one address a reverse proxy needs.";
    };

    trustedProxies = mkOption {
      type = types.listOf types.str;
      default = [
        "127.0.0.1/32"
        "::1/128"
      ];
      description = ''
        CIDRs whose X-Forwarded-For, -Proto and -Host headers the gateway keeps.
        The reverse proxy in front of Nocturne must be among them.
      '';
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        EnvironmentFile read by the API and the web server, delivered out of band.
        It must set `INSTANCE_KEY`, at least 32 characters, which signs tokens and
        encrypts the secrets Nocturne stores; losing it loses those secrets. Bot and
        mail credentials go here too. Nothing secret belongs in `api.settings` or
        `web.settings`, which are world-readable in the Nix store.
      '';
    };

    api = {
      package = mkOption {
        type = types.package;
        description = "Nocturne API package.";
      };

      port = mkOption {
        type = types.port;
        default = 5081;
        description = "Loopback port of the API.";
      };

      settings = mkOption {
        type = settingsType;
        default = { };
        description = ''
          Extra non-secret environment variables for the API. ASP.NET nests
          configuration keys with a double underscore.
        '';
        example = {
          Logging__LogLevel__Default = "Warning";
        };
      };
    };

    web = {
      package = mkOption {
        type = types.package;
        description = "Nocturne web package.";
      };

      port = mkOption {
        type = types.port;
        default = 5082;
        description = "Loopback port of the web server.";
      };

      settings = mkOption {
        type = settingsType;
        default = { };
        description = "Extra non-secret environment variables for the web server.";
        example = {
          ALLOWED_FRAME_ANCESTORS = "https://dashboard.example.org";
        };
      };
    };

    database = {
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Run a local PostgreSQL and create the database and Nocturne's three
          roles. The services reach it over its Unix socket with peer
          authentication, so no database password exists.
        '';
      };

      name = mkOption {
        type = types.str;
        default = "nocturne";
        description = "Database name.";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.postgresql_17;
        defaultText = lib.literalExpression "pkgs.postgresql_17";
        description = "PostgreSQL package, when the database is created locally.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database.createLocally;
        message = "services.nocturne: only a locally created database is supported so far.";
      }
      {
        assertion =
          !(builtins.any (s: s ? INSTANCE_KEY) [
            cfg.api.settings
            cfg.web.settings
          ]);
        message = ''
          services.nocturne: INSTANCE_KEY must not be set in api.settings or
          web.settings, which are world-readable in the Nix store. Put it in
          environmentFile.
        '';
      }
    ];

    services.postgresql = mkIf cfg.database.createLocally {
      enable = true;
      package = cfg.database.package;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = map (name: { inherit name; }) [
        "nocturne_migrator"
        "nocturne_app"
        "nocturne_web"
      ];
      identMap = ''
        nocturne nocturne-api nocturne_migrator
        nocturne nocturne-api nocturne_app
        nocturne nocturne-web nocturne_web
      '';
      authentication = ''
        local ${cfg.database.name} nocturne_migrator,nocturne_app,nocturne_web peer map=nocturne
      '';
    };

    systemd.services.nocturne-database = mkIf cfg.database.createLocally {
      description = "Nocturne database ownership and grants";
      after = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = [ "postgresql.service" ];
      wants = [ "postgresql-setup.service" ];
      path = [ cfg.database.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
      };
      script = ''
        psql --set ON_ERROR_STOP=on --dbname ${lib.escapeShellArg cfg.database.name} <<'SQL'
        ALTER ROLE nocturne_migrator LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
        ALTER ROLE nocturne_app LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
        ALTER ROLE nocturne_web LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
        ALTER DATABASE "${cfg.database.name}" OWNER TO nocturne_migrator;
        ALTER SCHEMA public OWNER TO nocturne_migrator;
        GRANT CONNECT ON DATABASE "${cfg.database.name}" TO nocturne_app, nocturne_web;
        GRANT USAGE ON SCHEMA public TO nocturne_app;
        GRANT USAGE, CREATE ON SCHEMA public TO nocturne_web;
        ALTER DEFAULT PRIVILEGES FOR ROLE nocturne_migrator IN SCHEMA public
          GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nocturne_app;
        ALTER DEFAULT PRIVILEGES FOR ROLE nocturne_migrator IN SCHEMA public
          GRANT USAGE, SELECT ON SEQUENCES TO nocturne_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO nocturne_app;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO nocturne_app;
        SQL
      '';
    };

    systemd.services.nocturne-api = {
      description = "Nocturne API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ databaseUnits;
      wants = [ "network-online.target" ];
      requires = databaseUnits;

      environment = {
        ASPNETCORE_ENVIRONMENT = "Production";
        ASPNETCORE_URLS = loopback cfg.api.port;
        ASPNETCORE_CONTENTROOT = "${cfg.api.package}/lib/nocturne-api";
        ASPNETCORE_FORWARDEDHEADERS_ENABLED = "true";
        DOTNET_gcServer = "0";
        DOTNET_GCConserveMemory = "5";
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
        BASE_DOMAIN = cfg.baseDomain;
        WEB_URL = loopback cfg.web.port;
        DemoService__Enabled = "false";
      }
      // lib.mapAttrs (_: render) cfg.api.settings;

      serviceConfig = hardening // {
        User = "nocturne-api";
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe cfg.api.package)
          "--ConnectionStrings:nocturne-postgres=${npgsql "nocturne_app"}"
          "--ConnectionStrings:nocturne-postgres-migrator=${npgsql "nocturne_migrator"}"
        ];
        EnvironmentFile = cfg.environmentFile;
        StateDirectory = "nocturne-api";
        WorkingDirectory = "/var/lib/nocturne-api";
        Environment = [ "HOME=/var/lib/nocturne-api" ];
        MemoryDenyWriteExecute = false;
      };
    };

    systemd.services.nocturne-web = {
      description = "Nocturne web server";
      wantedBy = [ "multi-user.target" ];
      after = [ "nocturne-api.service" ] ++ databaseUnits;
      requires = databaseUnits;

      environment = {
        PORT = toString cfg.web.port;
        HOST = "127.0.0.1";
        NOCTURNE_API_URL = loopback cfg.api.port;
        NOCTURNE_API_HTTP = loopback cfg.api.port;
        PUBLIC_API_URL = loopback cfg.api.port;
        BASE_DOMAIN = cfg.baseDomain;
        PROTOCOL_HEADER = "x-forwarded-proto";
        HOST_HEADER = "x-forwarded-host";
        NOCTURNE_POSTGRES_URI = "postgresql://nocturne_web@/${cfg.database.name}?host=${socket}";
      }
      // lib.mapAttrs (_: render) cfg.web.settings;

      serviceConfig = hardening // {
        User = "nocturne-web";
        ExecStart = lib.getExe cfg.web.package;
        EnvironmentFile = cfg.environmentFile;
        MemoryDenyWriteExecute = false;
      };
    };

    systemd.services.nocturne-gateway = {
      description = "Nocturne gateway";
      wantedBy = [ "multi-user.target" ];
      after = [
        "nocturne-api.service"
        "nocturne-web.service"
      ];

      serviceConfig = hardening // {
        User = "nocturne-gateway";
        ExecStart = "${lib.getExe pkgs.caddy} run --adapter caddyfile --config ${caddyfile}";
        StateDirectory = "nocturne-gateway";
        Environment = [
          "HOME=/var/lib/nocturne-gateway"
          "XDG_DATA_HOME=/var/lib/nocturne-gateway"
          "XDG_CONFIG_HOME=/var/lib/nocturne-gateway"
        ];
        AmbientCapabilities = lib.optional (cfg.port < 1024) "CAP_NET_BIND_SERVICE";
      };
    };
  };
}
