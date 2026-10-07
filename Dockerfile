FROM hexpm/elixir:1.19.5-erlang-28.1-debian-bookworm-20260112-slim AS build

RUN apt-get update -y && apt-get install -y --no-install-recommends \
  build-essential \
  git \
  curl \
  npm \
  ca-certificates && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim AS app

# git: Deploy pushes the static site (StaticSite.Deployer).
RUN apt-get update -y && apt-get install -y --no-install-recommends \
  git \
  libstdc++6 \
  openssl \
  libncurses6 \
  chromium \
  libxml2-utils \
  locales \
  ca-certificates && \
  rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

COPY --from=build /app/_build/prod/rel/playcode ./

RUN chown -R nobody:nogroup /app
USER nobody:nogroup

ENV HOME=/app
ENV PHX_SERVER=true
EXPOSE 8080

CMD ["/app/bin/playcode", "start"]
