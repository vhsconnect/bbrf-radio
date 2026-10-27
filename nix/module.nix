flake:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkDefault
    optional
    optionalAttrs
    types
    ;

  cfg = config.services.bbrf;
  dist = cfg.distribution;
  distributed = cfg.role != "all";
  peerRole = if cfg.role == "hub" then "ingest" else "hub";
  isIPv4 = addr: builtins.match "[0-9]+(\\.[0-9]+){3}" addr != null;

  # systemd puts LoadCredential= files here for a system service
  credentials = "/run/credentials/bbrf.service";

  # each side trusts only the CA that signs the other side; dud signs nothing
  trust = {
    hub = {
      server = "caI";
      client = "dud";
    };
    ingest = {
      server = "dud";
      client = "caH";
    };
  };

  distConf = pkgs.writeText "bbrf-${cfg.role}-dist.conf" ''
    [{server, [{cacertfile, "${dist.certificates}/${trust.${cfg.role}.server}.crt"},
               {certfile, "${dist.certificates}/${cfg.role}.crt"},
               {keyfile, "${credentials}/key"}, {secure_renegotiate, true},
               {verify, verify_peer}, {fail_if_no_peer_cert, true}]},
     {client, [{cacertfile, "${dist.certificates}/${trust.${cfg.role}.client}.crt"},
               {certfile, "${dist.certificates}/${cfg.role}.crt"},
               {keyfile, "${credentials}/key"}, {secure_renegotiate, true},
               {verify, verify_peer}]}].
  '';

  # the ingest node only connects out, so it listens on loopback where nothing else can reach it
  bind =
    if cfg.role == "ingest" then
      "127.0.0.1"
    else if isIPv4 dist.address then
      dist.address
    else
      null;

  erlFlags = lib.concatStringsSep " " (
    [
      "-name bbrf_${cfg.role}@${dist.address}"
      "-proto_dist inet_tls"
      "-ssl_dist_optfile ${distConf}"
      "-connect_all false"
      "-kernel inet_dist_listen_min ${toString dist.portMin} inet_dist_listen_max ${toString dist.portMax}"
    ]
    ++
      optional (bind != null)
        "-kernel inet_dist_use_interface {${lib.replaceStrings [ "." ] [ "," ] bind}}"
  );

  toEnv = value: if builtins.isBool value then (if value then "1" else "0") else toString value;
in
{
  options.services.bbrf = {
    enable = mkEnableOption "the bbrf radio server";

    package = mkOption {
      type = types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.bbrf;
      defaultText = lib.literalExpression "bbrf.packages.\${system}.bbrf";
      description = "The bbrf release; its frontend bundle is served from `static/` in it.";
    };

    role = mkOption {
      type = types.enum [
        "all"
        "hub"
        "ingest"
      ];
      default = "all";
      description = ''
        `all` runs the API and the ingester on one database. `hub` serves the API and receives
        syncs; `ingest` ingests and pushes to the hub. Both need {option}`services.bbrf.distribution`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 4882;
      description = "Port the API and the frontend listen on, on every interface.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open {option}`services.bbrf.port`.";
    };

    user = mkOption {
      type = types.str;
      default = "bbrf";
      description = "User the server runs as; created when left at the default.";
    };

    group = mkOption {
      type = types.str;
      default = "bbrf";
      description = "Group the server runs as; created when left at the default.";
    };

    ## Deprecated
    favoritesImportFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/lib/bbrf/storage.json";
      description = "Favorites imported at boot while the favorites table is empty.";
    };

    settings = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.bool
          types.int
          types.str
        ]
      );
      default = { };
      example = {
        RETENTION_DAYS = 90;
        FADER_VALUE = 25;
        BBRF_INGESTER = false;
      };
      description = ''
        Environment variables for the server, as in the repo's `.env`. Booleans become `1` and `0`.
      '';
    };

    distribution = {
      address = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "192.168.50.121";
        description = ''
          This node's address, as given to `secrets init` (`HUB_ADDR` or `INGEST_ADDR`). It is in
          the node name and the certificate.
        '';
      };

      peerAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "192.168.50.178";
        description = "The other node's address, as given to `secrets init`.";
      };

      certificates = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = lib.literalExpression "./secrets";
        description = ''
          Directory from `secrets init` with `caI.crt`, `caH.crt`, `dud.crt` and this node's
          certificate. Only public files are read from it; it is copied to the store.
        '';
      };

      keyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path of this node's TLS private key; set from `sopsFile` when that is used.";
      };

      cookieFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path of the distribution cookie; set from `sopsFile` when that is used.";
      };

      sopsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = lib.literalExpression "./secrets/hub.enc.yaml";
        description = ''
          This node's `<role>.enc.yaml` from `secrets init`, decrypted with sops-nix (which has to
          be imported) into {option}`keyFile` and {option}`cookieFile`. sops-nix decrypts with
          the host's SSH key by default, or `sops.age.keyFile`.
        '';
      };

      portMin = mkOption {
        type = types.port;
        default = 9100;
        description = "Lowest distribution port.";
      };

      portMax = mkOption {
        type = types.port;
        default = 9105;
        description = "Highest distribution port.";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          On a hub, open epmd (4369) and the distribution ports to every host, or only on
          {option}`firewallInterface`. The ingest node needs nothing open.
        '';
      };

      firewallInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "enp3s0";
        description = ''
          Interface {option}`openFirewall` opens the ports on, e.g. the LAN one when the hub is
          also reachable from outside. All interfaces when unset.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions =
        map
          (name: {
            assertion = !distributed || dist.${name} != null;
            message = "services.bbrf.distribution.${name} is required for role ${cfg.role}";
          })
          [
            "address"
            "peerAddress"
            "certificates"
          ]
        ++
          map
            (name: {
              assertion = !distributed || dist.${name} != null;
              message = "services.bbrf.distribution.${name} is required for role ${cfg.role}; set it, or sopsFile with sops-nix imported";
            })
            [
              "keyFile"
              "cookieFile"
            ];

      users.users = optionalAttrs (cfg.user == "bbrf") {
        bbrf = {
          isSystemUser = true;
          inherit (cfg) group;
        };
      };
      users.groups = optionalAttrs (cfg.group == "bbrf") { bbrf = { }; };

      networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

      systemd.services.bbrf = {
        description = "bbrf radio server";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        environment =
          lib.mapAttrs (_: toEnv) cfg.settings
          // {
            BBRF_ROLE = cfg.role;
            PORT = toString cfg.port;
            BBRF_DB = "/var/lib/bbrf/db.sqlite";
            STATIC_DIR = "${cfg.package}/static";
            RELEASE_TMP = "/run/bbrf";
            # the node name and the TLS flags come from ELIXIR_ERL_OPTIONS
            RELEASE_DISTRIBUTION = "none";
            # the start script requires one; a distributed node replaces it from BBRF_COOKIE_FILE at boot
            RELEASE_COOKIE = "bbrf-placeholder";
          }
          // optionalAttrs (cfg.favoritesImportFile != null) {
            FAVORITES_IMPORT_FILE = cfg.favoritesImportFile;
          }
          // optionalAttrs distributed {
            ELIXIR_ERL_OPTIONS = erlFlags;
            BBRF_COOKIE_FILE = "${credentials}/cookie";
            ${if cfg.role == "hub" then "SYNC_INGEST_NODE" else "SYNC_HUB_NODE"} =
              "bbrf_${peerRole}@${dist.peerAddress}";
          }
          // optionalAttrs (distributed && bind != null) {
            # only takes effect when this node is the one starting epmd
            ERL_EPMD_ADDRESS = bind;
          };

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/bbrf start";
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "bbrf";
          RuntimeDirectory = "bbrf";
          WorkingDirectory = "/var/lib/bbrf";
          Restart = "on-failure";
          LoadCredential = lib.optionals distributed [
            "key:${dist.keyFile}"
            "cookie:${dist.cookieFile}"
          ];

          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    }

    (mkIf (cfg.role == "hub" && dist.openFirewall) (
      let
        ports = {
          allowedTCPPorts = [ 4369 ];
          allowedTCPPortRanges = [
            {
              from = dist.portMin;
              to = dist.portMax;
            }
          ];
        };
      in
      {
        networking.firewall = mkMerge [
          (mkIf (dist.firewallInterface == null) ports)
          (mkIf (dist.firewallInterface != null) { interfaces.${dist.firewallInterface} = ports; })
        ];
      }
    ))

    (optionalAttrs (options ? sops) (
      mkIf (distributed && dist.sopsFile != null) {
        sops.secrets = lib.genAttrs [ "bbrf/key" "bbrf/cookie" ] (name: {
          inherit (dist) sopsFile;
          key = lib.removePrefix "bbrf/" name;
          restartUnits = [ "bbrf.service" ];
        });
        services.bbrf.distribution = {
          keyFile = mkDefault config.sops.secrets."bbrf/key".path;
          cookieFile = mkDefault config.sops.secrets."bbrf/cookie".path;
        };
      }
    ))
  ]);
}
