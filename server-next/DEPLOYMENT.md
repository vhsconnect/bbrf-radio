# Deploying a hub and an ingest node

bbrf can run on one machine (`BBRF_ROLE=all`, the default: nothing on this page applies) or split over two:

- **hub**: a small machine, reachable from outside. Serves the frontend, the API and the favorites, and keeps a window of track history (`RETENTION_DAYS`, e.g. 30 days, about 2-3 GB). Never ingests.
- **ingest**: a bigger machine, internal, not necessarily always on. Runs the ingester and keeps the full history.

Both run the same code and the same command, `make server`; `.env` decides the role. Both databases have the same schema. Every 10 minutes the ingest node checks whether a sync is due (once a day by default) and, if so, connects to the hub over Erlang distribution, pushes every station and the observations the hub does not have yet, and disconnects. The hub never connects anywhere.

The link is mutual TLS with one private CA per role: only the ingest node's certificate is accepted by the hub, and the hub's own client side trusts nothing, so it cannot connect out. A shared cookie is the second check. Each node's TLS key and the cookie are kept in a [sops](https://github.com/getsops/sops) file encrypted to that node's [age](https://age-encryption.org) key and an admin key. See `BBRF.Sync` and `scripts/launch.fish` for the details.

## Before you start

- Both machines: this repo, and either [Nix](https://nixos.org) with flakes (`nix develop` provides Erlang, Elixir, sqlite, fish, openssl, sops and age; the `make` targets use it) or those tools installed by hand.
- The two machines can reach each other on the LAN, the hub at a fixed address.
- The admin machine (where the certificates are made) can be either node or a third machine.
- For moving existing favorites: `curl` and `jq`.

Below, `HUB` and `INGEST` stand for the two addresses, e.g. `192.168.50.121` and `192.168.50.178`. An IP or a hostname both work; it has to be the address the other side dials, since it ends up in the node names (`bbrf_hub@HUB`, `bbrf_ingest@INGEST`) and the certificates.

## 1. An age key on each node

On the hub and on the ingest node:

    make age-key

This creates `~/.config/bbrf/age.key` (override with `AGE_KEY_FILE`) and prints its public key, `age1...`. The private key never leaves the machine; back it up somewhere safe. The public key is not secret: send it to the admin machine any way you like.

## 2. Certificates and secrets, on the admin machine

Put the addresses and the two public keys in the admin machine's `.env` (or answer the prompts):

    HUB_ADDR=192.168.50.121
    INGEST_ADDR=192.168.50.178
    HUB_AGE=age1...
    INGEST_AGE=age1...

Then:

    make secrets

It creates, in `secrets/`:

| File | What |
|---|---|
| `caI.crt`, `caH.crt` | the CAs that sign the ingest node and the hub |
| `dud.crt` | a CA that signs nothing; trusting it means trusting nobody |
| `hub.crt`, `ingest.crt` | the node certificates, valid 1 year |
| `hub.enc.yaml`, `ingest.enc.yaml` | node name, cookie and TLS key, each readable only by that node and the admin |
| `.sops.yaml` | those recipients, for `sops updatekeys` |

and finishes with `make secrets-check`. Afterwards:

- Move the CA private keys (`~/.local/share/bbrf/ca`) offline, to an encrypted drive or a password manager. They are only needed to issue certificates again.
- Back up the admin age key (`~/.config/sops/age/keys.txt`, sops's default; created if it did not exist). It opens both node files.

## 3. Copy `secrets/` to the other node

`secrets/` is gitignored: it belongs to your deployment, not to the project. Copy it into the repo on whichever node is not the admin machine, e.g.:

    scp -r secrets/ HUB:path/to/bbrf-radio/

Nothing in it is readable without the right age key.

## 4. `.env` on each node

On the hub:

    BBRF_ROLE=hub
    SYNC_INGEST_NODE=bbrf_ingest@INGEST
    RETENTION_DAYS=30

On the ingest node:

    BBRF_ROLE=ingest
    SYNC_HUB_NODE=bbrf_hub@HUB
    RETENTION_DAYS=365

The ingest node keeps the database it already has (`BBRF_DB`, or `$STATE_DIR/db.sqlite` with `make`). `SYNC_INTERVAL_HOURS` (24) sets how often it syncs.

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

## 6. Favorites, when coming from one machine

Favorites live on the hub and are never synced. To bring over the ones from an existing single-machine setup, before the hub's first start:

    curl http://OLD_SERVER:4882/favorites | jq '{favorites: .}' > storage.json

and set `FAVORITES_IMPORT_FILE=/path/to/storage.json` in the hub's `.env`. They are imported at boot while the hub's favorites table is empty.

## 7. Bring them up

On both machines, in either order:

    make server

The launcher prints the node it starts, e.g. `==> hub node bbrf_hub@192.168.50.121, TLS distribution on 192.168.50.121 ports 9100-9105`. The hub serves the API right away, with empty history until the first sync. The first sync sends every station and the hub's whole retention window, which can take a few minutes; later ones send a day's worth.

Check that it worked:

- the hub logs `sync: started by bbrf_ingest@INGEST`
- the ingest node logs `job=sync ... sync rows=<observations> inserted=<observations> updated=<stations> ...`
- `/tracks` on the hub returns plays

## Upgrades

Deploy the same version to both machines. When a version brings a migration, the hub refuses syncs until both sides run it, logging `sync: refused, the hub is at migration X and the ingest node at Y`; nothing is lost, the next sync after both are upgraded catches up. The order does not matter.

## Certificates

`make secrets-check` on the admin machine warns when a certificate has less than 30 days left. For now renewing means running `make secrets` again (with `FORCE=1` or confirming), which replaces the CAs, the certificates and the cookie, and copying `secrets/` to the other node again; the age keys stay. The same is the way to rotate after a leak, plus new age keys (`rm` the key file, `make age-key`) for a node whose key leaked.

## Troubleshooting

A failed sync is logged as a warning on the ingest node, ending in the reason, and retried within 10 minutes:

| Reason | Meaning |
|---|---|
| `{:unreachable, :"bbrf_hub@..."}` | No connection: the hub is down, the firewall blocks 4369 or 9100-9105, `SYNC_HUB_NODE` has the wrong address, or the TLS handshake or cookie was refused. For those, the hub logs `TLS :server: ... Unknown CA` for a certificate it does not trust, `Unexpected Message` for a node without TLS, or a rejected connection attempt for a wrong cookie |
| `:not_distributed` | The ingest node was not started through `make server` / `scripts/launch.fish` with `BBRF_ROLE=ingest` |
| `{:schema_mismatch, hub, ingest}` | The two run different versions; upgrade the older one |
| `:not_allowed` | The hub's `SYNC_INGEST_NODE` does not match the ingest node's name |
| `{:columns_mismatch, table}` | A table was changed by hand on one side |

The launcher stops with a message when the node's age key or `secrets/<role>.enc.yaml` is missing, or when the file was encrypted to another key.

There is no remote shell into the hub: it accepts no certificate but the ingest node's. Use its log.
