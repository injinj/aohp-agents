# aohp-agents

Agent distribution layer for [AOHP](https://github.com/aohp-os/aohp) containers — the
"Omarchy" idea applied to phone agents: the rootfs template stays a thin Debian base,
everything agent-specific comes from git.

```
aohp-bootstrap <github-user>/<config-repo>      # one command on a fresh container
```

- **This repo (public)** — installers for agent systems and the secrets resolver.
  Cloned to `/opt/aohp-agents`; `aohp-update` pulls it.
- **Your config repo (private)** — your `~/.openclaw` (config, workspace, skills), with
  secrets either age-encrypted in the repo, kept in the phone's keystore, or pasted once.

## Bootstrap flow

1. `gh auth login --web` — an 8-character device code you enter at github.com/login/device
   from any browser (the phone's, or your laptop's). Non-interactive: `--token-file <f>`.
2. `git clone <your config repo>` onto `~/.openclaw` (dotfiles-style: works on an existing
   state dir, tracked files are checked out, runtime state is left alone).
3. Secrets method — `--secrets age|keystore|paste` or an interactive menu:
   - **age**: `secrets/env.age` in your repo, decrypted with a passphrase (or `--age-identity`)
     to `~/.openclaw/.env` (mode 600).
   - **keystore**: nothing on disk; the launcher asks the AgentDriver app
     (`aohp secret get VAR`) which answers from the Android Keystore. Requires an app build
     with the secret store.
   - **paste**: type each required variable once; written to `~/.openclaw/.env`.
4. Runs `install/<agent>.sh` for each agent listed in your repo's `agents` file
   (default: `openclaw`).

`openclaw.json` in your repo never contains a secret — use `${ANTHROPIC_API_KEY}`-style
references; OpenClaw expands them from the environment, and the launcher wrapper installed by
`install/openclaw.sh` supplies the environment from whichever method you picked.

## Installers

| script | installs |
|---|---|
| `install/openclaw.sh` | OpenClaw gateway (npm), secrets-aware `openclaw` wrapper |
| `install/claude-code.sh` | Claude Code CLI (npm) |
| `install/codex.sh` | OpenAI Codex CLI (npm) |
| `install/opencode.sh` | OpenCode (official installer) |

Each is idempotent and safe to re-run. `aohp-update` = `git pull` + re-run the installers
listed in your config repo.

## Layout of a config repo

```
openclaw.json           # with ${VAR} references, no secrets
workspace/              # AGENTS.md, SOUL.md, skills/ …
secrets/required        # one VAR per line, e.g. ANTHROPIC_API_KEY
secrets/env.age         # (age method) age -p encrypted KEY=value lines
agents                  # one installer name per line (default: openclaw)
.gitignore              # runtime state: agents/ cache/ media/ state/ tmp/ .env *.last-good …
```
