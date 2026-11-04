
-include .env
export

NIX := nix develop -c
PORT ?= 4882
NODE ?= bbrf
BBRF_API ?= 1
BBRF_INGESTER ?= 1
DB ?= $(STATE_DIR)/db.sqlite
FAVORITES_IMPORT_FILE ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/bbrf-radio/storage.json
SECRETS_DIR ?= $(CURDIR)/secrets
AGE_KEY_DIR ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/bbrf

.PHONY: dev dev-all dev-api dev-ingester deps server docker docker-stop attach frontend test status status-watch age-key secrets secrets-renew secrets-check

dev: dev-all

dev-all: deps
	$(MAKE) -j2 server frontend

dev-api: BBRF_INGESTER = 0
dev-api: deps server

dev-ingester: BBRF_API = 0
dev-ingester: deps server

deps:
	$(NIX) pnpm install
	cd server-next && $(NIX) mix deps.get

server: docker-stop
	mkdir -p $(STATE_DIR)
	cd server-next && \
		PORT=$(PORT) \
		STATIC_DIR=$(CURDIR) \
		BBRF_DB=$(DB) \
		FAVORITES_IMPORT_FILE=$(FAVORITES_IMPORT_FILE) \
		BBRF_API=$(BBRF_API) \
		BBRF_INGESTER=$(BBRF_INGESTER) \
		$(NIX) ../scripts/launch.fish elixir -S mix run --no-halt

# server, as a release in Docker; .env picks the role here too. The mounted directories are
# created first so Docker does not create them as root
docker:
	mkdir -p $(STATE_DIR) $(SECRETS_DIR) $(AGE_KEY_DIR)
	docker compose up -d --build bbrf

# the container shares $(STATE_DIR) with the local server, and two ingesters on one sqlite file lock each other out;
# '-' keeps going on machines without docker
docker-stop:
	-docker compose stop bbrf

attach:
	$(NIX) iex --sname probe --remsh $(NODE)@$(shell hostname -s)

frontend:
	$(NIX) pnpm run build && \
	$(NIX) pnpm run hot

test:
	cd server-next && $(NIX) mix test

status:
	$(NIX) sqlite3 -readonly $(DB) < server-next/scripts/status.sql

status-watch:
	$(NIX) watch -t -n 10 "sqlite3 -readonly '$(DB)' < server-next/scripts/status.sql"

# hub + ingest deployment: run age-key on each node, then secrets once on the admin machine
age-key:
	$(NIX) scripts/secrets.fish age-key

secrets:
	$(NIX) scripts/secrets.fish init

secrets-renew:
	$(NIX) scripts/secrets.fish renew

secrets-check:
	$(NIX) scripts/secrets.fish check
