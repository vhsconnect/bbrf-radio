# BBRF - Barebones radio with a fader

BBRF radio is a lightweight downstream client to the delightful [radio-browser](https://de1.api.radio-browser.info/) api - a hosted service that serves metadata on all openly available online radios. You can run bbrf as a self-hosted stateful server or client only through [bbrf.vhsconnect.link](https://bbrf.vhsconnect.link)

## Client only

Use this to test the server or for using bbrf as a radio bookmarking tool with a convenience media player. For most people this is the way to go. The app is stateless, all your favorites will be saved through the url - so you'll need to re-bookmark the url everytime you add or remove a favorite. The limitation here is the 4096 character limit in the url. So expect the site to stop loading after 12 - 15 favorites more or less. If you're using your phone and bookmarking the app a firefox/chromium shortcut - you can create various shortcuts for different types of radio (News, Classical, World, etc...) - that's what I do.

## Server

To get started, Start up the server, or better yet host it on your network's raspberry pi or set it up as a `systemd` service. The app is served on port `4882` (`PORT` in `.env`) to be accessed on your browser.


### Quick start hub and/or ingest server

Needs Erlang/OTP 28, Elixir and pnpm, all in `nix develop`.

```sh
pnpm install && pnpm run build
cd server-next
mix deps.get
STATIC_DIR=.. mix run --no-halt
```

The server listens on port 4881 (`PORT`) and keeps its database in `server-next/data/bbrf.sqlite` (`BBRF_DB`). Any variable from `.env` can be set the same way.

### Usage with docker

Copy `.env.example` to `.env` and modify ports or environment variables such as `FADER_VALUE` there; `make docker` and docker compose read it.

```
make docker
```


### Usage with nixos

This repo's flake exports a NixOS module that runs the server as a systemd service (`bbrf.service`, state in `/var/lib/bbrf`).

```nix
{
  inputs.bbrf.url = "github:vhsconnect/bbrf-radio/master";

  outputs = inputs: {
    nixosConfigurations.mySystem = inputs.nixpkgs.lib.nixosSystem {
      modules = [ inputs.bbrf.nixosModules.default ];
    };
  };
}
```

then in your configuration

```nix
{
  services.bbrf = {
    enable = true;
    role = "all"; # or "hub" / "ingest", see server-next/DEPLOYMENT.md
    port = 4882;
    openFirewall = true;
    # any variable from .env
    settings = {
      FADER_VALUE = 25;
      ITEMS_PER_PAGE = 5000;
    };
  };
}
```

For a hub and an ingest node on two machines, see the NixOS section of `server-next/DEPLOYMENT.md`.

### Running developer build

You can run the elixir server and bundle the frontend yourself with `mix` and `pnpm`. We provide some nice developer commands through our GNU makefile using the nix package manager. All configuration options can be tweaked in the .env file. Take a look at the .env.example file for a list of all configurable options.

You can run the application in development mode.

```bash
make dev-all
```
You can run the application without the ingester

```bash
make dev-api
```
Or with ingester only

```bash
make dev-ingester
```
