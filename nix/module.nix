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
  isIPv4 = addr: builtins.match "[0-9]+(\\.[0-9]+){3}" addr != null;

  # the names are those `secrets` gives the files: hub, ingest, ingest-<suffix>
  roleOf = name: if name == "hub" then "hub" else "ingest";
  addressOf = lib.listToAttrs (map (n: lib.nameValuePair n.name n.address) cfg.nodes);
  nodeName = name: "bbrf_${roleOf name}@${addressOf.${name}}";
  ingestNames = lib.filter (name: name != "hub") (map (n: n.name) cfg.nodes);
  addedIngestNames = lib.filter (name: name != "ingest") ingestNames;

  secretsScript =
    let
      bin = lib.getExe flake.packages.${pkgs.stdenv.hostPlatform.system}.bbrf-secrets;
      addIngest = name: ''
        INGEST_NAME=${name} INGEST_ADDR=${addressOf.${name}} INGEST_AGE=ssh ${bin} add-ingest
      '';
    in
    pkgs.writeShellScriptBin "bbrf-secrets" ''
      set -eu
      case "$*" in
        init)
          HUB_ADDR=${addressOf.hub} HUB_AGE=ssh INGEST_ADDR=${addressOf.ingest} INGEST_AGE=ssh ${bin} init
          ${lib.concatMapStrings addIngest addedIngestNames}
          ;;
        ${lib.concatMapStrings (name: ''
          add-ingest\ ${name}) ${addIngest name} ;;
        '') addedIngestNames}
        *)
          exec ${bin} "$@"
          ;;
      esac
    '';

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
    [{server, [{cacertfile, "${cfg.secrets}/${trust.${cfg.role}.server}.crt"},
               {certfile, "${cfg.secrets}/${cfg.node}.crt"},
               {keyfile, "${credentials}/key"}, {secure_renegotiate, true},
               {verify, verify_peer}, {fail_if_no_peer_cert, true}]},
     {client, [{cacertfile, "${cfg.secrets}/${trust.${cfg.role}.client}.crt"},
               {certfile, "${cfg.secrets}/${cfg.node}.crt"},
               {keyfile, "${credentials}/key"}, {secure_renegotiate, true},
               {verify, verify_peer}]}].
  '';

  # the ingest node only connects out, so it listens on loopback where nothing else can reach it
  bind =
    if cfg.role == "ingest" then
      "127.0.0.1"
    else if isIPv4 addressOf.${cfg.node} then
      addressOf.${cfg.node}
    else
      null;

  erlFlags = lib.concatStringsSep " " (
    [
      "-name ${nodeName cfg.node}"
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
  imports = [
    (lib.mkRemovedOptionModule [
      "services"
      "bbrf"
      "faderValue"
    ] "Use services.bbrf.settings.FADER_VALUE instead.")
    (lib.mkRemovedOptionModule [
      "services"
      "bbrf"
      "itemsPerPage"
    ] "Use services.bbrf.settings.ITEMS_PER_PAGE instead.")
    (lib.mkRemovedOptionModule [ "services" "bbrf" "serveStaticSite" ]
      "The module no longer serves the client-only build; use https://bbrf.vhsconnect.link or serve pages/ from the bbrf-radio package yourself."
    )
    (lib.mkRemovedOptionModule [
      "services"
      "bbrf"
      "staticSiteServedOn"
    ] "Removed along with services.bbrf.serveStaticSite.")
    (lib.mkRemovedOptionModule [
      "services"
      "bbrf"
      "favoritesImportFile"
    ] "Favorites are no longer imported from a node server's storage.json.")
  ];

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
      default = if cfg.node != null then roleOf cfg.node else "all";
      defaultText = lib.literalMD "`hub` or `ingest`, from {option}`services.bbrf.node`; `all` without one";
      description = ''
        `all` runs the API and the ingester on one database. `hub` serves the API and receives
        syncs; `ingest` ingests and pushes to the hub.
      '';
    };

    nodes = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "ingest-2";
              description = ''
                Its file names in {option}`services.bbrf.secrets`: `hub`, `ingest` for the first
                ingest node and `ingest-<suffix>` for the others.
              '';
            };

            address = mkOption {
              type = types.str;
              example = "192.168.50.179";
              description = "The address its distribution listens on.";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          name = "hub";
          address = "192.168.50.121";
        }
        {
          name = "ingest";
          address = "192.168.50.178";
        }
        {
          name = "ingest-2";
          address = "192.168.50.179";
        }
      ];
      description = ''
        Every node of the deployment, the same on each machine. The hub syncs with every ingest
        node listed, in this order.

        `config.system.build.bbrf-secrets` runs `secrets` for these nodes, encrypting to their SSH
        host keys: `init` creates every node's files, `add-ingest <name>` one added later, and the
        other commands pass through. It writes to `SECRETS_DIR`, `secrets` by default.
      '';
    };

    node = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ingest-2";
      description = "Which of {option}`services.bbrf.nodes` this machine is.";
    };

    secrets = mkOption {
      type = types.path;
      example = lib.literalExpression "./secrets/bbrf";
      description = ''
        Directory from `secrets` with the certificates and the `<name>.enc.yaml` files. With
        sops-nix imported, this node's file is decrypted into
        {option}`services.bbrf.distribution.keyFile` and
        {option}`services.bbrf.distribution.cookieFile`.
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
      keyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path of this node's TLS private key; set by sops-nix when it is imported.";
      };

      cookieFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path of the distribution cookie; set by sops-nix when it is imported.";
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
          On a hub, open epmd (4369) and the distribution ports to the ingest nodes' addresses.
          The ingest nodes need nothing open.
        '';
      };
    };
  };

  # nix-darwin has no systemd; without this guard it fails on an undefined option before any assertion is shown
  config =
    if !(options ? systemd) then
      {
        assertions = [
          {
            assertion = !cfg.enable;
            message = "services.bbrf runs on NixOS only; launchd (nix-darwin) support was removed in 0.11.0.";
          }
        ];
      }
    else
      mkIf cfg.enable (mkMerge [
        {
          assertions =
            map
              (name: {
                assertion = !distributed || dist.${name} != null;
                message = "services.bbrf.distribution.${name} is required for role ${cfg.role}; set it, or import sops-nix";
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

          system.build.bbrf-secrets = secretsScript;

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
              // optionalAttrs distributed {
                ELIXIR_ERL_OPTIONS = erlFlags;
                BBRF_COOKIE_FILE = "${credentials}/cookie";
              }
              // optionalAttrs (cfg.role == "hub") {
                SYNC_INGEST_NODE = lib.concatMapStringsSep "," nodeName ingestNames;
              }
              // optionalAttrs (cfg.role == "ingest") {
                SYNC_HUB_NODE = nodeName "hub";
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
            addresses = map (name: addressOf.${name}) ingestNames;
            portMin = toString dist.portMin;
            portMax = toString dist.portMax;
          in
          {
            networking.firewall = mkMerge [
              (mkIf config.networking.nftables.enable {
                extraInputRules = "ip saddr { ${lib.concatStringsSep ", " addresses} } tcp dport { 4369, ${portMin}-${portMax} } accept";
              })
              (mkIf (!config.networking.nftables.enable) {
                extraCommands = lib.concatMapStrings (address: ''
                  iptables -A nixos-fw -p tcp -s ${address} --dport 4369 -j nixos-fw-accept
                  iptables -A nixos-fw -p tcp -s ${address} --dport ${portMin}:${portMax} -j nixos-fw-accept
                '') addresses;
              })
            ];
          }
        ))

        (optionalAttrs (options ? sops) (
          mkIf distributed {
            sops.secrets = lib.genAttrs [ "bbrf/key" "bbrf/cookie" ] (name: {
              sopsFile = cfg.secrets + "/${cfg.node}.enc.yaml";
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
