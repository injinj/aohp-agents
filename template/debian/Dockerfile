# AOHP agent-container rootfs template: Debian trixie (glibc 2.41, gcc 14, Python 3.13), official Node, OpenClaw.
# Build with template/build-template.sh debian <arm64|amd64> (podman build --platform; see template/README.md).
ARG AOHP_CLI_IMAGE=localhost/aohp-cli:latest
FROM --platform=$BUILDPLATFORM $AOHP_CLI_IMAGE AS aohp-cli

FROM docker.io/library/debian:trixie-slim
ARG NODE_VERSION=v24.21.0
ARG OPENCLAW_VERSION=2026.9.6
ARG AOHP_AGENTS_REPO=https://github.com/injinj/aohp-agents.git
ARG AOHP_AGENTS_REF=main
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Same package set as the former /aosp/templates/build-debian-template.sh (debootstrap --variant=minbase --include=...),
# plus wireguard-tools + openssh-server (installed, nothing enabled; see common/net/ and README "Network services").
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git bash jq sqlite3 procps xz-utils less nano openssh-client \
      python3 python3-pip python3-venv build-essential pkg-config cmake gdb strace file unzip zip \
      iproute2 iputils-ping netbase tzdata gh age \
      wireguard-tools openssh-server \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

COPY common/ /tmp/provision/
RUN NODE_VERSION=$NODE_VERSION sh /tmp/provision/node-install.sh

COPY --from=aohp-cli /src/cli/aohp/dist/aohp.js /usr/local/bin/aohp
COPY --from=aohp-cli /src/skills/ /opt/aohp-skills/
COPY --from=aohp-cli /src/AOHP_COMMIT /opt/aohp-skills/.aohp-commit
RUN chmod 755 /usr/local/bin/aohp \
 && OPENCLAW_VERSION=$OPENCLAW_VERSION AOHP_AGENTS_REPO=$AOHP_AGENTS_REPO AOHP_AGENTS_REF=$AOHP_AGENTS_REF bash /tmp/provision/agent-layer.sh \
 && sh /tmp/provision/cleanup.sh
CMD ["/bin/bash"]
