# Builder image for the aohp CLI (dist/aohp.js, a single esbuild bundle -> arch-independent) and the AOHP skills.
# Built once on the host platform by template/build-template.sh as localhost/aohp-cli:<ref>; the distro Dockerfiles
# COPY --from it (FROM --platform=$BUILDPLATFORM, so arm64 template builds reuse the native build).
# Source: injinj/aohp branch feat/cli-secret (= aohp-os/aohp main + 'aohp secret get|set|delete|list', which the
# keystore secrets method of aohp-agents needs). Neither injinj/aohp nor aohp-os/aohp publishes a prebuilt CLI.
FROM docker.io/library/node:24-bookworm-slim
ARG AOHP_REPO=https://github.com/injinj/aohp.git
ARG AOHP_REF=feat/cli-secret
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone -q --depth 1 --branch "$AOHP_REF" "$AOHP_REPO" /src \
 && cd /src/cli/aohp && npm ci --no-fund --no-audit && npm run build \
 && node dist/aohp.js --help | grep -q '^ *secret' \
 && git -C /src rev-parse HEAD > /src/AOHP_COMMIT && rm -rf /src/cli/aohp/node_modules
# results: /src/cli/aohp/dist/aohp.js, /src/skills/, /src/AOHP_COMMIT
