# Local development without docker. Every command runs inside the flake's
# dev shell so node, pnpm, erlang and elixir come from the same pins.
#
#   make dev-all       install deps, then the server (api + ingester) and the frontend watcher
#   make dev-api       install deps, then the server with only the api, on PORT
#   make dev-ingester  install deps, then the server with only the ingester
#   make dev           same as dev-all
#   make server        only the server, no dependency install
#   make frontend      only the esbuild watcher, writing ./index.js and reloading open pages on rebuild
#   make test          the server's test suite
#   make status        where the ingester stands, read from the database (DB=path for another one)
#   make status-watch  the same, refreshed every 10 seconds

NIX := nix develop -c
PORT ?= 4882
BBRF_API ?= 1
BBRF_INGESTER ?= 1
STATE_DIR ?= $(HOME)/.local/state/bbrf
DB ?= $(STATE_DIR)/db.sqlite
FAVORITES_IMPORT_FILE ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/bbrf-radio/storage.json

.PHONY: dev dev-all dev-api dev-ingester deps server frontend test status status-watch

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

server:
	mkdir -p $(STATE_DIR)
	cd server-next && \
		PORT=$(PORT) \
		STATIC_DIR=$(CURDIR) \
		BBRF_DB=$(DB) \
		FAVORITES_IMPORT_FILE=$(FAVORITES_IMPORT_FILE) \
		BBRF_API=$(BBRF_API) \
		BBRF_INGESTER=$(BBRF_INGESTER) \
		$(NIX) mix run --no-halt

frontend:
	$(NIX) pnpm run build && \
	$(NIX) pnpm run hot

test:
	cd server-next && $(NIX) mix test

status:
	$(NIX) sqlite3 -readonly $(DB) < server-next/scripts/status.sql

status-watch:
	$(NIX) watch -t -n 10 "sqlite3 -readonly '$(DB)' < server-next/scripts/status.sql"
