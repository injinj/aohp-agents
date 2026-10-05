# AOHP agent-container rootfs template: Arch Linux (rolling: newest glibc/gcc/Python), official Node, OpenClaw.
# Build with template/build-template.sh arch <arm64|amd64>.
#   amd64: docker.io/library/archlinux:base-devel (official Docker library image, amd64 only).
#   arm64: official Arch has no aarch64 -> Arch Linux ARM via docker.io/menci/archlinuxarm:base-devel (community image,
#          GitHub Actions-built from the ALARM generic aarch64 tarball; multi-arch incl. linux/arm64). Third-party trust
#          level — see template/README.md. ALARM packages can lag mainline Arch by days.
# build-template.sh passes the right ARCH_IMAGE per arch.
ARG AOHP_CLI_IMAGE=localhost/aohp-cli:latest
ARG ARCH_IMAGE=docker.io/library/archlinux:base-devel
FROM --platform=$BUILDPLATFORM $AOHP_CLI_IMAGE AS aohp-cli

FROM $ARCH_IMAGE
ARG NODE_VERSION=v24.21.0
ARG OPENCLAW_VERSION=2026.9.6
ARG AOHP_AGENTS_REPO=https://github.com/injinj/aohp-agents.git
ARG AOHP_AGENTS_REF=main
ENV LANG=C.UTF-8

# Equivalent of the Debian set. base-devel = gcc 16, make, binutils, pkgconf, patch, autotools, debugedit (which pulls
# gdb, and with it guile + boost-libs, ~140 MB — unavoidable on Arch). cmake is deliberately NOT included (another
# ~100 MB incl. cmake-gui/ccmake; 'pacman -S cmake' adds it). The official image already NoExtracts man/doc/locale;
# we add a few more data-only trees (i18n sources, udev hwdb, hwdata, GIR, gcc multilib libs).
# DisableSandbox: pacman 7's download sandbox (Landlock + the 'alpm' user) is unavailable under qemu-user and on
# Android kernels (no CONFIG_SECURITY_LANDLOCK in GKI); without it 'pacman -Sy' fails before downloading anything.
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf \
 && sed -i '/^\[options\]/a NoExtract = usr/share/doc/* usr/share/man/* usr/share/info/* usr/share/gtk-doc/* usr/share/i18n/* usr/share/locale/* usr/lib/udev/hwdb.d/* usr/share/hwdata/* usr/share/gir-1.0/* usr/lib/gcc/*/*/32/* usr/share/groff/* usr/share/texinfo/*' /etc/pacman.conf \
 && (pacman-key --init && pacman-key --populate) >/dev/null 2>&1 || true \
 && pacman -Syu --noconfirm --needed \
      base-devel git python python-pip jq sqlite procps-ng xz tar gzip less nano openssh file unzip zip iproute2 iputils \
      github-cli age ca-certificates curl wget strace which inetutils wireguard-tools openssh \
 && pacman -Scc --noconfirm >/dev/null \
 && rm -rf /var/cache/pacman/pkg/*
RUN readelf -n /usr/lib/libc.so.6 | grep -E 'OS: Linux' || true
# Arch's gdb embeds Guile. aohp-containerd's extractor does not restore mtimes, so on the device Guile's precompiled
# .go files look older than their .scm sources and 'gdb' (even 'gdb --version') auto-compiles Guile for ~2 minutes
# on first use. GUILE_AUTO_COMPILE=0 makes Guile load the shipped .go files regardless (observed Cuttlefish 2026-10-04).
RUN printf '#!/bin/sh\nexport GUILE_AUTO_COMPILE=${GUILE_AUTO_COMPILE:-0}\nexec /usr/bin/gdb "$@"\n' > /usr/local/bin/gdb && chmod 755 /usr/local/bin/gdb \
 && printf 'export GUILE_AUTO_COMPILE=0\n' > /etc/profile.d/guile-no-autocompile.sh

COPY common/ /tmp/provision/
RUN NODE_VERSION=$NODE_VERSION sh /tmp/provision/node-install.sh

COPY --from=aohp-cli /src/cli/aohp/dist/aohp.js /usr/local/bin/aohp
COPY --from=aohp-cli /src/skills/ /opt/aohp-skills/
COPY --from=aohp-cli /src/AOHP_COMMIT /opt/aohp-skills/.aohp-commit
RUN chmod 755 /usr/local/bin/aohp \
 && OPENCLAW_VERSION=$OPENCLAW_VERSION AOHP_AGENTS_REPO=$AOHP_AGENTS_REPO AOHP_AGENTS_REF=$AOHP_AGENTS_REF bash /tmp/provision/agent-layer.sh \
 && sh /tmp/provision/cleanup.sh
CMD ["/bin/bash"]
