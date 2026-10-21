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

FROM ${RUNTIME_IMAGE} AS runtime

# the release bundles ERTS but still links against the system OpenSSL and
# ncurses; CA certificates are needed for the radio-browser / icecast HTTPS calls
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libncurses6 libssl3 libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/_build/prod/rel/bbrf ./
COPY --from=web /app/index.js /app/index.html /app/styles.css /app/favicon-16x16.png ./static/

ENV BBRF_DB=/data/db.sqlite \
    STATIC_DIR=/app/static \
    PORT=4881

EXPOSE 4881

CMD ["/app/bin/bbrf", "start"]
