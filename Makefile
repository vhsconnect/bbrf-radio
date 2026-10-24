
-include .env
export

NIX := nix develop -c
PORT ?= 4882
NODE ?= bbrf
BBRF_API ?= 1
BBRF_INGESTER ?= 1
DB ?= $(STATE_DIR)/db.sqlite
FAVORITES_IMPORT_FILE ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/bbrf-radio/storage.json

.PHONY: dev dev-all dev-api dev-ingester deps server attach frontend test status status-watch

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
		$(NIX) elixir --sname $(NODE) -S mix run --no-halt

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
