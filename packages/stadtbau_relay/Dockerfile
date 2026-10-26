# SPDX-License-Identifier: AGPL-3.0-or-later
# The Hectopolis relay as one static-ish executable on an empty base.
# Build from this directory:   docker build -t hectopolis-relay .
# It serves plain ws:// on port 8080; put a TLS proxy in front (see
# docs/relay-hosting.md), because the game only connects over wss://.
FROM dart:3.12 AS build
WORKDIR /relay
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY bin ./bin
COPY lib ./lib
RUN dart compile exe bin/relay.dart -o /out/relay

FROM scratch
# The Dart runtime's minimal system libraries, as the official image intends.
COPY --from=build /runtime/ /
COPY --from=build /out/relay /relay
# Nobody: the relay needs no privileges and no writable filesystem.
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/relay", "--address", "0.0.0.0", "--port", "8080"]
