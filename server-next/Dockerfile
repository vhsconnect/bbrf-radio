# Build context is the bbrf-radio repo root, because the frontend bundle is
# built from src/ here:  docker build -f server-next/Dockerfile .
ARG NODE_IMAGE=node:26-alpine
ARG ELIXIR_IMAGE=hexpm/elixir:1.19.6-erlang-28.5.0.8-debian-bookworm-20261005-slim
ARG RUNTIME_IMAGE=debian:bookworm-slim

FROM ${NODE_IMAGE} AS web

WORKDIR /app

RUN npm install -g pnpm@10

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY tsconfig.json index.html styles.css favicon-16x16.png ./
COPY src ./src
COPY server ./server
RUN pnpm run build

FROM ${ELIXIR_IMAGE} AS build

ENV MIX_ENV=prod

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY server-next/mix.exs server-next/mix.lock ./
RUN mix deps.get --only prod

COPY server-next/config config
COPY server-next/priv priv
COPY server-next/lib lib

RUN mix deps.compile && mix release

FROM ${RUNTIME_IMAGE} AS sops

# the checksums belong to this version, from its release's checksums.txt
ARG SOPS_VERSION=3.13.3
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && case "$TARGETARCH" in \
         amd64) sum=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b ;; \
         arm64) sum=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77 ;; \
         *) echo "no sops checksum for $TARGETARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /sops "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${TARGETARCH}" \
    && echo "$sum  /sops" | sha256sum -c - \
    && chmod 755 /sops

FROM ${RUNTIME_IMAGE} AS runtime

# the release bundles ERTS but still links against the system OpenSSL and
# ncurses; CA certificates are needed for the radio-browser / icecast HTTPS calls.
# fish and sops run the launcher, which decrypts a hub's or ingest node's secrets
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libncurses6 libssl3 libstdc++6 fish \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=sops /sops /usr/local/bin/sops
COPY --from=build /app/_build/prod/rel/bbrf ./
COPY --from=web /app/index.js /app/index.html /app/styles.css /app/favicon-16x16.png ./static/
COPY scripts/launch.fish ./

# SECRETS_DIR, AGE_KEY_FILE and RUNTIME_DIR are only read for BBRF_ROLE hub or ingest
ENV LANG=C.UTF-8 \
    BBRF_DB=/data/db.sqlite \
    STATIC_DIR=/app/static \
    PORT=4881 \
    SECRETS_DIR=/secrets \
    AGE_KEY_FILE=/age/age.key \
    RUNTIME_DIR=/run/bbrf

EXPOSE 4881

ENTRYPOINT ["/app/launch.fish"]
CMD ["/app/bin/bbrf", "start"]
