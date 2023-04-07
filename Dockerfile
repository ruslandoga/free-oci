#########
# BUILD #
#########

FROM hexpm/elixir:1.14.4-erlang-25.3-alpine-3.17.2 as build

RUN apk add --no-cache --update git build-base

RUN mkdir /app
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get
RUN mix deps.compile

COPY lib lib
RUN mix compile
COPY config/runtime.exs config/

RUN mix release

#######
# APP #
#######

FROM alpine:3.17.2 AS app
RUN apk add --no-cache --update openssl libgcc libstdc++ ncurses

WORKDIR /app

RUN chown nobody:nobody /app
USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/o ./

ENV HOME=/app

CMD /app/bin/o start
