#!/bin/bash
# OpenClaw launcher for AOHP containers (installed as /usr/local/bin/openclaw by aohp-agents/install/openclaw.sh;
# the rootfs templates in template/ ship the same file). The real npm binary is /usr/local/bin/openclaw.real.
# 1) secrets: export provider keys from the method chosen at bootstrap (age/paste -> ~/.openclaw/.env, keystore -> aohp secret get)
# 2) aohp-containerd injects NODE_OPTIONS=--jitless into container services; Node 24 fetch() needs WebAssembly, so strip it.
if command -v aohp-secrets >/dev/null 2>&1; then eval "$(aohp-secrets env 2>/dev/null)"; fi
NODE_OPTIONS=$(printf '%s' "${NODE_OPTIONS:-}" | sed -e 's/--jitless//g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//'); export NODE_OPTIONS
# 3) the containerd service environment has no SHELL, so openclaw would run exec commands under dash; bash sets an *unexported* SHELL when the env lacks one, so export unconditionally (OnePlus lesson 2026-10-04).
if [ -x /bin/bash ]; then export SHELL=/bin/bash; fi
exec /usr/local/bin/openclaw.real "$@"
