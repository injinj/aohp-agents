# AOHP agent-container rootfs template: Fedora 44 (glibc 2.41, gcc 15, Python 3.14), official Node, OpenClaw.
# Build with template/build-template.sh fedora <arm64|amd64>. Base: registry.fedoraproject.org/fedora:44 (multi-arch:
# amd64 + arm64 published).
ARG AOHP_CLI_IMAGE=localhost/aohp-cli:latest
ARG FEDORA_IMAGE=registry.fedoraproject.org/fedora:44
FROM --platform=$BUILDPLATFORM $AOHP_CLI_IMAGE AS aohp-cli

FROM $FEDORA_IMAGE
ARG NODE_VERSION=v24.21.0
ARG OPENCLAW_VERSION=2026.9.6
ARG AOHP_AGENTS_REPO=https://github.com/injinj/aohp-agents.git
ARG AOHP_AGENTS_REF=main
ENV LANG=C.UTF-8

# Equivalent of the Debian set. No weak deps, no docs. curl replaces the image's curl-minimal (--allowerasing).
# SELinux: the container runs chrooted on an Android kernel whose selinuxfs is visible but whose policy knows nothing
# about Fedora file contexts. Make sure nothing in rpm/dnf tries to label files: no rpm selinux plugin, no policy,
# and /etc/selinux/config (if a package shipped it) says disabled.
RUN dnf -y install --allowerasing --setopt=install_weak_deps=False --setopt=tsflags=nodocs \
      gcc gcc-c++ glibc-devel libstdc++-devel make cmake gdb strace git python3 python3-pip jq sqlite procps-ng \
      xz tar gzip bzip2 less nano openssh-clients file unzip zip iproute iputils tzdata gh age ca-certificates \
      curl wget findutils which pkgconf-pkg-config diffutils patch hostname \
 && dnf -y clean all && rm -rf /var/cache/dnf /var/cache/libdnf5 /var/cache/yum /var/log/dnf* /var/log/hawkey.log \
 && (rpm -q rpm-plugin-selinux >/dev/null 2>&1 && dnf -y remove rpm-plugin-selinux || true) \
 && (rpm -q selinux-policy >/dev/null 2>&1 && dnf -y remove selinux-policy || true) \
 && if [ -f /etc/selinux/config ]; then sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config; fi \
 && dnf -y clean all && rm -rf /var/cache/dnf /var/cache/libdnf5

COPY common/ /tmp/provision/
RUN NODE_VERSION=$NODE_VERSION sh /tmp/provision/node-install.sh

COPY --from=aohp-cli /src/cli/aohp/dist/aohp.js /usr/local/bin/aohp
COPY --from=aohp-cli /src/skills/ /opt/aohp-skills/
COPY --from=aohp-cli /src/AOHP_COMMIT /opt/aohp-skills/.aohp-commit
RUN chmod 755 /usr/local/bin/aohp \
 && OPENCLAW_VERSION=$OPENCLAW_VERSION AOHP_AGENTS_REPO=$AOHP_AGENTS_REPO AOHP_AGENTS_REF=$AOHP_AGENTS_REF bash /tmp/provision/agent-layer.sh \
 && sh /tmp/provision/cleanup.sh
CMD ["/bin/bash"]
