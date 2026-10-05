# AOHP agent-container rootfs template: Arch Linux (rolling: newest glibc/gcc/Python), official Node, OpenClaw.
# Build with template/build-template.sh arch <arm64|amd64>.
#   amd64: docker.io/library/archlinux:base-devel (official Docker library image, amd64 only).
#   arm64: official Arch has no aarch64 -> Arch Linux ARM via docker.io/menci/archlinuxarm:base-devel (community image,
#          GitHub Actions-built from the ALARM generic aarch64 tarball; multi-arch incl. linux/arm64). Third-party trust
#          level — see template/README.md. ALARM packages can lag mainline Arch by days.
# build-template.sh passes the right ARCH_IMAGE per arch.
ARG AOHP_CLI_IMAGE=localhost/aohp-cli:latest
ARG BUILDPLATFORM=linux/amd64
FROM --platform=$BUILDPLATFORM $AOHP_CLI_IMAGE AS aohp-cli

ARG ARCH_IMAGE=docker.io/library/archlinux:base-devel
FROM $ARCH_IMAGE
ARG NODE_VERSION=v24.21.0
ARG OPENCLAW_VERSION=2026.9.6
ARG AOHP_AGENTS_REPO=https://github.com/injinj/aohp-agents.git
ARG AOHP_AGENTS_REF=main
ENV LANG=C.UTF-8

# Equivalent of the Debian set (base-devel = gcc, make, binutils, pkgconf, patch, ...). Skip docs/man/info.
RUN sed -i 's|^#\?NoExtract.*|NoExtract = usr/share/doc/* usr/share/man/* usr/share/info/* usr/share/gtk-doc/*|' /etc/pacman.conf \
 && grep -q '^NoExtract' /etc/pacman.conf || sed -i 's|^\[options\]|[options]\nNoExtract = usr/share/doc/* usr/share/man/* usr/share/info/* usr/share/gtk-doc/*|' /etc/pacman.conf \
 && (pacman-key --init && pacman-key --populate) >/dev/null 2>&1 || true \
 && pacman -Syu --noconfirm --needed \
      base-devel git python python-pip jq sqlite procps-ng xz tar gzip less nano openssh file unzip zip iproute2 iputils \
      github-cli age ca-certificates curl wget cmake gdb strace which inetutils \
 && pacman -Scc --noconfirm >/dev/null \
 && rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*.sig \
 && readelf -n /usr/lib/libc.so.6 | grep -E 'OS: Linux' || true

COPY common/ /tmp/provision/
RUN NODE_VERSION=$NODE_VERSION sh /tmp/provision/node-install.sh

COPY --from=aohp-cli /src/cli/aohp/dist/aohp.js /usr/local/bin/aohp
COPY --from=aohp-cli /src/skills/ /opt/aohp-skills/
COPY --from=aohp-cli /src/AOHP_COMMIT /opt/aohp-skills/.aohp-commit
RUN chmod 755 /usr/local/bin/aohp \
 && OPENCLAW_VERSION=$OPENCLAW_VERSION AOHP_AGENTS_REPO=$AOHP_AGENTS_REPO AOHP_AGENTS_REF=$AOHP_AGENTS_REF bash /tmp/provision/agent-layer.sh \
 && sh /tmp/provision/cleanup.sh
CMD ["/bin/bash"]
