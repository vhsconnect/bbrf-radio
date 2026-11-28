# Deploying a hub and an ingest node

bbrf can run on one machine (`BBRF_ROLE=all`, the default: nothing on this page applies) or split over two:

- **hub**: a small machine, reachable from outside. Serves the frontend, the API and the favorites, and keeps a window of track history (`RETENTION_DAYS`, e.g. 90 days, about 5-10 GB). Never ingests.
- **ingest**: a bigger machine, internal, not necessarily always on. Runs the ingester and keeps the full history.

Both run the same code and the same command, `make server`, or `make docker` for a release in Docker; `.env` decides the role. Both databases have the same schema. Every 10 minutes the ingest node checks whether a sync is due (once a day by default) and, if so, connects to the hub over Erlang distribution, pushes every station, the artist catalogue and the observations the hub does not have yet, and disconnects. The hub never connects anywhere. Several ingest nodes can push to one hub (see [Another ingest node](#another-ingest-node)); each polls every station on its own, and the hub drops a play another node already sent within 10 minutes.

The link is mutual TLS with one private CA per role: only the ingest node's certificate is accepted by the hub, and the hub's own client side trusts nothing, so it cannot connect out. A shared cookie is the second check. Each node's TLS key and the cookie are kept in a [sops](https://github.com/getsops/sops) file encrypted to that node's [age](https://age-encryption.org) key and an admin key. See `BBRF.Sync` and `scripts/launch.fish` for the details.

## Before you start

- Both machines: this repo, and either [Nix](https://nixos.org) with flakes (`nix develop` provides Erlang, Elixir, sqlite, fish, openssl, sops and age; the `make` targets use it) or those tools installed by hand.
- For `make docker`: Docker with compose as well. The image brings its own fish and sops; `make age-key` and `make secrets` still run through Nix.
- The two machines can reach each other on the LAN, the hub at a fixed address.
- An admin machine, where `make secrets` runs once and the CA keys stay afterwards. Make it the ingest node (or a third machine), never the hub, which is reachable from outside. Running `make secrets` again, here or anywhere else, makes new CAs and replaces the whole deployment.
- For moving existing favorites: `curl` and `jq`.

Either node can run on NixOS through the flake's module instead of `make server` or `make docker` (see [NixOS](#nixos)); a NixOS hub with a Docker ingest node, or the other way round, works as long as both run the same version.

Below, `HUB` and `INGEST` stand for the two addresses, e.g. `192.168.50.121` and `192.168.50.178`. An IP or a hostname both work; it has to be the address the other side dials, since it ends up in the node names (`bbrf_hub@HUB`, `bbrf_ingest@INGEST`) and the certificates.

## 1. An age key on each node

On the hub and on the ingest node:

    make age-key

This creates `~/.config/bbrf/age.key` (override with `AGE_KEY_FILE`) and prints its public key, `age1...`. The private key never leaves the machine; back it up somewhere safe. The public key is not secret: send it to the admin machine any way you like.

A NixOS node with sops-nix needs no age key of its own: sops-nix decrypts with the host's SSH key. Skip this step for it and answer `ssh` for its age key in step 2.

## 2. Certificates and secrets, on the admin machine

Put the addresses and the two public keys in the admin machine's `.env` (or answer the prompts):

    HUB_ADDR=192.168.50.121
    INGEST_ADDR=192.168.50.178
    HUB_AGE=age1...
    INGEST_AGE=age1...

`HUB_AGE=ssh` (or `INGEST_AGE=ssh`) derives that node's age key from its SSH host key in `~/.ssh/known_hosts` (override with `KNOWN_HOSTS`), so ssh to it once from the admin machine first.

Then:

    make secrets

or, without a checkout, `nix run github:vhsconnect/bbrf-radio#secrets -- init` (also `renew` and `check`).

It creates, in `secrets/`:

| File | What |
|---|---|
| `caI.crt`, `caH.crt` | the CAs that sign the ingest node and the hub |
| `dud.crt` | a CA that signs nothing; trusting it means trusting nobody |
| `hub.crt`, `ingest.crt` | the node certificates, valid 1 year |
| `hub.enc.yaml`, `ingest.enc.yaml` | node name, cookie and TLS key, each readable only by that node and the admin |
| `.sops.yaml` | those recipients, for `sops updatekeys` |

and finishes with `make secrets-check`. Afterwards:

- The CA private keys stay in `~/.local/share/bbrf/ca`, where `make secrets-renew` needs them. That is fine on an admin machine that is not the hub; to be stricter, move them offline and bring them back to renew.
- Back up the admin age key (`~/.config/sops/age/keys.txt`, sops's default; created if it did not exist). It opens both node files.

## 3. Copy `secrets/` to the other node

`secrets/` is gitignored: it belongs to your deployment, not to the project. Copy it into the repo on whichever node is not the admin machine, e.g.:

    scp -r secrets/ HUB:path/to/bbrf-radio/

Nothing in it is readable without the right age key.

## 4. `.env` on each node

Start from the example, `cp .env.example .env`, then set the role.

On the hub:

    BBRF_ROLE=hub
    SECRETS_NAME=hub
    SYNC_INGEST_NODE=bbrf_ingest@INGEST
    RETENTION_DAYS=90

On the ingest node:

    BBRF_ROLE=ingest
    SECRETS_NAME=ingest
    SYNC_HUB_NODE=bbrf_hub@HUB
    RETENTION_DAYS=365

The ingest node keeps the database it already has (`BBRF_DB`, or `$STATE_DIR/db.sqlite` with `make`). `SYNC_INTERVAL_HOURS` (24) sets how often it syncs. History grows by 55-110 MB a day, so 90 days on the hub is 5-10 GB.

With `make docker`, the container reads the whole `.env`, as `make server` and `make metrics` do, except for the paths, which point inside it: `BBRF_DB`, `STATIC_DIR`, `SECRETS_DIR`, `AGE_KEY_FILE` and `RUNTIME_DIR`. It mounts `secrets/` read-only and reads the node's age key as `age.key` in `AGE_KEY_DIR` (default `~/.config/bbrf`, where `make age-key` puts it). The decrypted TLS key and cookie live in a tmpfs inside the container. `HOST_UID` and `HOST_GID` (1000 and 100) set the user it runs as, which has to own the database and be able to read the age key.

## 5. Hub firewall

The hub needs epmd (4369) and the distribution ports (9100-9105) open to the ingest node only, and its API port (`PORT`) as open as you want it. The ingest node listens for distribution on loopback only and needs nothing open.

On NixOS (iptables, the default firewall backend):

```nix
networking.firewall.allowedTCPPorts = [ 4882 ]; # the API, PORT in .env
networking.firewall.extraCommands = ''
  iptables -A nixos-fw -p tcp -s 192.168.50.178 --dport 4369 -j nixos-fw-accept
  iptables -A nixos-fw -p tcp -s 192.168.50.178 --dport 9100:9105 -j nixos-fw-accept
'';
```

With `networking.nftables.enable = true`, use `networking.firewall.extraInputRules = "ip saddr 192.168.50.178 tcp dport { 4369, 9100-9105 } accept";` instead.

## 6. Bring them up

On both machines, in either order:

    make server    # or: make docker, then docker logs -f bbrf

The launcher prints the node it starts, e.g. `==> hub node bbrf_hub@192.168.50.121, TLS distribution on 192.168.50.121 ports 9100-9105`. The hub serves the API right away, with empty history until the first sync. The first sync sends every station and the hub's whole retention window, which can take a few minutes; later ones send a day's worth.

Check that it worked:

- the hub logs `sync: started by bbrf_ingest@INGEST`
- the ingest node logs `job=sync ... sync rows=<observations> inserted=<observations> updated=<stations> ...`
- `/tracks` on the hub returns plays

## Station metrics

Metrics are not computed on a schedule: run them by hand on the hub (or the `all` node) with `make metrics`, or through the container; see [docs/cli.md](../docs/cli.md). They score the last `METRICS_WINDOW_DAYS` (60) of plays, so keep the hub's `RETENTION_DAYS` at least that long.

## Upgrades

Deploy the same version to both machines. When a version brings a migration, the hub refuses syncs until both sides run it, logging `sync: refused, the hub is at migration X and the ingest node at Y`; nothing is lost, the next sync after both are upgraded catches up. The order does not matter.

The upgrade that numbers observations per ingest node (migration `20261120120012`) hands the hub's existing history to the first node in its `SYNC_INGEST_NODE`, so start the hub with `BBRF_ROLE=hub` and `SYNC_INGEST_NODE` set for it. A hub that misses it is sent its whole retention window again, once, and keeps both copies.

## Certificates

The node certificates last a year and the CAs five. `make secrets-check` on the admin machine fails when a node certificate has less than 30 days left, or when a CA expires before a renewed certificate would.

To renew, on the admin machine:

    make secrets-renew

It issues new node keys and certificates from the same CAs, and swaps the key in each node's file without touching its cookie or recipients. Copy `secrets/` to the other node, then restart each node when convenient. Both CAs are unchanged, so a renewed node and one not renewed yet still trust each other.

To rotate after a leak, or when the CAs are near their end, run `make secrets` again (with `FORCE=1` or confirming). That replaces the CAs, the certificates and the cookie, so copy `secrets/` over and restart both nodes. Give a node whose age key leaked a new one first (`rm` the key file, `make age-key`).

## Another ingest node

After `make secrets`, on the admin machine, give the new node an age key (`make age-key` on it) and run:

    INGEST_NAME=ingest-2 INGEST_ADDR=192.168.50.179 INGEST_AGE=age1... make secrets-add-ingest

It issues `ingest-2.crt` from the same CA as the first ingest node and writes `ingest-2.enc.yaml` with the same cookie, readable by the new node and the admin. `make secrets-renew` and `make secrets-check` cover it from then on. Then:

- copy `secrets/` to the new node, and set `SECRETS_NAME=ingest-2` next to `BBRF_ROLE=ingest` in its `.env` (on NixOS, `distribution.name = "ingest-2"` and `sopsFile = ./secrets/ingest-2.enc.yaml`)
- add `bbrf_ingest@192.168.50.179` to the hub's `SYNC_INGEST_NODE`, comma separated (on NixOS, `settings.SYNC_INGEST_NODE` with every ingest node), open the hub's firewall to its address, and restart the hub

With a hub on 192.168.50.121 and ingest nodes on 192.168.50.178 and 192.168.50.179, the `.env` files read:

    # hub
    BBRF_ROLE=hub
    SECRETS_NAME=hub
    SYNC_INGEST_NODE=bbrf_ingest@192.168.50.178,bbrf_ingest@192.168.50.179

    # first ingest node
    BBRF_ROLE=ingest
    SECRETS_NAME=ingest
    SYNC_HUB_NODE=bbrf_hub@192.168.50.121

    # ingest-2
    BBRF_ROLE=ingest
    SECRETS_NAME=ingest-2
    SYNC_HUB_NODE=bbrf_hub@192.168.50.121

## NixOS
Pre-req
1. Every machine runs NixOS with sops-nix imported, and its SSH host key enabled; 
2. Describe the deployment once, in a shared module
```nix
  services.bbrf = {
    enable = true;
    nodes = [
      { name = "hub";      address = "192.168.50.121"; }
      { name = "ingest";   address = "192.168.50.178"; }
      { name = "ingest-2"; address = "192.168.50.179"; }
    ];
    secrets = ./secrets/bbrf;
  };
```
3. Names must be hub, ingest, ingest-<suffix>.
4. The order of the ingest nodes is the order the hub syncs them in.
5. Generate the secrets on the first machine
`SECRETS_DIR=secrets/bbrf nix run .#nixosConfigurations.<host>.config.system.build.bbrf-secrets -- init`. It creates the CAs, one certificate per node, and one encrypted file per node, readable only by that host and the admin. The admin age key and the CA private keys stay on this machine, outside the repo. Back them up.
6. Commit and roll out. Rebuild each machine, in any order. sops-nix decrypts that machine's own file, and the service starts with the right role, node name and sync targets.

## Troubleshooting

A failed sync is logged as a warning on the ingest node, ending in the reason, and retried within 10 minutes:

| Reason | Meaning |
|---|---|
| `{:unreachable, :"bbrf_hub@..."}` | No connection: the hub is down, the firewall blocks 4369 or 9100-9105, `SYNC_HUB_NODE` has the wrong address, or the TLS handshake or cookie was refused. For those, the hub logs `TLS :server: ... Unknown CA` for a certificate it does not trust, `Unexpected Message` for a node without TLS, or a rejected connection attempt for a wrong cookie |
| `:not_distributed` | The ingest node was not started through `make server` / `scripts/launch.fish` with `BBRF_ROLE=ingest` |
| `{:schema_mismatch, hub, ingest}` | The two run different versions; upgrade the older one |
| `:not_allowed` | The ingest node's name is not in the hub's `SYNC_INGEST_NODE` |
| `{:columns_mismatch, table}` | A table was changed by hand on one side |

The launcher stops with a message when the node's age key or `secrets/<role>.enc.yaml` is missing, or when the file was encrypted to another key. On NixOS the same shows up as `sops-install-secrets` failing during `nixos-rebuild`, and `bbrf.service` not starting for lack of its credentials.

There is no remote shell into the hub: it accepts no certificate but the ingest node's. Use its log.
