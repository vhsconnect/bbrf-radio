# Local development without docker. Every command runs inside the flake's
# dev shell so node, pnpm, erlang and elixir come from the same pins.
#
#   make dev-all   install deps, then the Elixir server and the frontend watcher
#   make dev-api   install deps, then only the Elixir server on PORT, with station ingest off
#   make dev       same as dev-all
#   make server    only the Elixir server, no dependency install
#   make frontend  only the esbuild watcher, writing ./index.js
#   make test      the Elixir test suite

NIX := nix develop -c
PORT ?= 4882
BBRF_INGESTION ?= 1
STATE_DIR ?= $(HOME)/.local/state/bbrf-elixir
FAVORITES_IMPORT_FILE ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/bbrf-radio/storage.json

.PHONY: dev dev-all dev-api deps server frontend test

dev: dev-all

dev-all: deps
	$(MAKE) -j2 server frontend

dev-api: BBRF_INGESTION = 0
dev-api: deps server

deps:
	$(NIX) pnpm install
	cd server-elixir && $(NIX) mix deps.get

server:
	mkdir -p $(STATE_DIR)
	cd server-elixir && \
		PORT=$(PORT) \
		STATIC_DIR=$(CURDIR) \
		RADIO_ANALYZER_DB=$(STATE_DIR)/db.sqlite \
		FAVORITES_IMPORT_FILE=$(FAVORITES_IMPORT_FILE) \
		BBRF_INGESTION=$(BBRF_INGESTION) \
		$(NIX) mix run --no-halt

frontend:
	$(NIX) pnpm run build && \
	$(NIX) pnpm run hot

test:
	cd server-elixir && $(NIX) mix test
