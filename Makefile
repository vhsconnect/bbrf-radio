
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

CYAN   := \033[36m
PURPLE := \033[35m
RESET  := \033[0m

# $(call prefix,<color>,<label>) tags each line of a piped stream with a colored label
prefix = 2>&1 | while IFS= read -r line; do printf '$(1)[$(2)]$(RESET) %s\n' "$$line"; done

.PHONY: dev dev-all dev-api dev-ingester deps build server docker docker-stop attach frontend test metrics favorites-export status status-watch age-key secrets secrets-renew secrets-add-ingest secrets-check

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

# the bundle the server serves from STATIC_DIR; no prefix pipe, so a failed build stops the target
build:
	$(NIX) pnpm run build

server: docker-stop build
	mkdir -p $(STATE_DIR)
	cd server-next && \
		PORT=$(PORT) \
		STATIC_DIR=$(CURDIR) \
		BBRF_DB=$(DB) \
		FAVORITES_IMPORT_FILE=$(FAVORITES_IMPORT_FILE) \
		BBRF_API=$(BBRF_API) \
		BBRF_INGESTER=$(BBRF_INGESTER) \
		$(NIX) ../scripts/launch.fish elixir -S mix run --no-halt \
		$(call prefix,$(CYAN),server)

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
	$(NIX) pnpm run hot $(call prefix,$(PURPLE),frontend)

test:
	cd server-next && $(NIX) mix test

# station metrics, computed once against $(DB); fine next to a running server
metrics:
	cd server-next && BBRF_DB=$(DB) $(NIX) mix run --no-start -e "BBRF.Metrics.CLI.main()"

# favorites from $(DB) to stdout, in the shape GET /favorites returns; '@' and the compile
# to stderr keep everything but the JSON off stdout
favorites-export:
	@cd server-next && BBRF_DB=$(DB) $(NIX) sh -c "mix compile >&2 && mix run --no-compile --no-start -e 'BBRF.Favorites.CLI.main()'"

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

secrets-add-ingest:
	$(NIX) scripts/secrets.fish add-ingest

secrets-check:
	$(NIX) scripts/secrets.fish check
