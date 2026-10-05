#!/bin/sh
# Distro-independent cleanup run as the last RUN step of every template Dockerfile.
set -eu
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/locale/* 2>/dev/null || true
rm -rf /root/.npm /root/.cache /tmp/* /var/tmp/* /var/log/* 2>/dev/null || true
find / -xdev \( -name '*.pyc' -o -name '__pycache__' \) -prune -exec rm -rf {} + 2>/dev/null || true
# source maps and tests inside the global node_modules are dead weight on a phone
find /usr/local/lib/node_modules -xdev -name '*.map' -type f -delete 2>/dev/null || true
mkdir -p /tmp/openclaw && chmod 1777 /tmp && chmod 700 /tmp/openclaw
mkdir -p /dev /proc /sys /run
