# Upstream PR drafts (not yet opened — awaiting Chris's go)

## aohp-os/AOHPAgentDriverApp ← injinj:pr/secret-store
**Title:** Keystore-backed secret store for sandbox agents (secret.get/set/delete/list RPC)

Provider API keys for agents in the Linux sandbox currently have to be written in clear text into the container rootfs (`~/.openclaw/openclaw.json`), and the app has no UI or API for them at all — the LLM-config screen only feeds udagen. This adds a named-secret store backed by `EncryptedSharedPreferences` with an Android Keystore master key (same construction as `UdaConfigStore`) and exposes it on the JSON-RPC bridge: `secret.get/set/delete/list` (names `[A-Z][A-Z0-9_]{0,63}`, `list` returns names only). `meta.version` advertises `features: ["secrets"]`.

With the matching CLI (aohp-os/aohp PR), a launcher in the container does `export ANTHROPIC_API_KEY=$(aohp secret get ANTHROPIC_API_KEY)` and nothing secret ever touches the rootfs; rotating/revoking is an app-side operation.

Tested on OnePlus 13 (arm64 AOHP GSI, Enforcing): `aohp secret set` from the sandbox, OpenClaw gateway started as the `openclaw-gateway` service with the key resolved from the keystore, model requests 200, `.env`/plaintext absent from the rootfs. A Settings screen to enter/rotate secrets from the phone UI would be the natural follow-up; this PR is the storage + bridge half. Consumer: https://github.com/injinj/aohp-agents (bootstrap with `--secrets keystore`).

## aohp-os/aohp ← injinj:pr/cli-secret
**Title:** cli: `aohp secret get|set|delete|list` (keystore-backed secrets from the Agent app)

Pairs with AOHPAgentDriverApp#<n>. `set` reads the value from stdin when no argument is given (keeps keys out of shell history/process lists); `get` prints the raw value for launchers; `list` is names only. Rebuilt `dist/aohp.js` included.
