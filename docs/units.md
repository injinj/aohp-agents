# Units — systemd-style services inside AOHP containers

AOHP containers have no PID namespace and no init: there is nothing for systemd or dinit to be
PID 1 of. Since the 2026-10-05 ROMs (oriole build-5 / dodge build-3, aohp-containerd with
`UNIT` ops, AOHP Driver 0.4.0) the Android-side daemon **aohp-containerd** supervises
*units* declared in the container instead — the same subset of systemd that runs OpenClaw on a
Linux box (`Restart=on-failure`, ordering, timers), with a `systemctl` shim so habits and
scripts keep working.

Full specification (supported keys, states, protocol): aohp-driver
[docs/UNITS.md](https://github.com/injinj/aohp-driver/blob/master/docs/UNITS.md).

## What the template ships (`/opt/aohp-agents/units/` → `/etc/aohp/system/`)

| unit | enabled | what |
|---|---|---|
| `openclaw-gateway.service` | **yes** | `/usr/local/bin/openclaw gateway`, `Restart=on-failure`, `RestartSec=5`, `SuccessExitStatus=0 143`, `EnvironmentFile=-/root/.openclaw/env.sh`, `WorkingDirectory=/root/.openclaw/workspace`, `After=wg0.service sshd.service`, `Wants=wg0.service` |
| `wg0.service` | no | oneshot `wg-quick up wg0` / `ExecStop=wg-quick down wg0`, `RemainAfterExit=yes`, `ConditionPathExists=/etc/wireguard/wg0.conf` |
| `sshd.service` | no | `ExecStartPre` mkdir /run/sshd + `ssh-keygen -A` + `sshd -t`; `sshd -D -E /var/log/sshd.log`; `ConditionPathExists=/etc/ssh/sshd_config.d/10-aohp.conf`; `After/Wants=wg0.service` |
| `net-watchdog.service` + `.timer` | no | one pass of `wg0-sshd-startup.sh` 2 min after env start, then every 5 min |
| `openclaw-watchdog.service` + `.timer` | no | `openclaw-watchdog.sh`: GET `/health` on :18789, 3 consecutive failures → `systemctl restart openclaw-gateway`; 3 min after env start, then every 2 min |

"Enabled" = symlink in `/etc/aohp/system/aohp.target.wants/`. **Env start** (what the Driver's
*Autostart* does at boot, `systemctl default`, `aohp unit <env> env-start`) starts every enabled
unit in `After=`/`Before=` order, pulling in `Requires=`/`Wants=`.

## Inside the container

```sh
systemctl status openclaw-gateway        # ● openclaw-gateway.service - OpenClaw gateway / Loaded / Active / Main PID / Restart …
systemctl restart openclaw-gateway
journalctl -u openclaw-gateway -n 100    # the unit log (/data/aohp/envs/<env>/.aohp/log/openclaw-gateway.log on the Android side)
systemctl list-units
systemctl list-timers
systemctl enable --now wg0 sshd          # after installing wg0.conf + the sshd drop-in (see README "Network services")
systemctl enable --now net-watchdog.timer openclaw-watchdog.timer
systemctl daemon-reload                  # after editing /etc/aohp/system/*.service
systemctl is-active sshd && echo up
```

These are **shims** (`/usr/local/bin/systemctl`, `/usr/local/bin/journalctl`, from this repo's
`bin/`): they forward to `aohp unit "$(cat /etc/aohp/env-name)" …`, which talks to the Driver bridge
(ws://127.0.0.1:6666, method `sandbox.unit`) → Binder `IAohpContainer.unitControl` → containerd.
Supported verbs: `list-units list-timers list-unit-files status start stop restart reload enable
disable [--now] is-active is-enabled is-failed daemon-reload reset-failed cat show`; `journalctl -u
UNIT [-n N] [-f]`. Not there: `--user`, `edit`, `mask`, `show -p`, socket/path units, targets other
than `aohp.target`. Debian's real `/usr/bin/systemctl` (pulled in by openssh-server) is shadowed by
PATH order and would only print "System has not been booted with systemd" anyway.

## From chex / any host over the bridge

```sh
aohp --url ws://PHONE:6666 unit oc list
aohp unit oc status openclaw-gateway
aohp unit oc start sshd            # pulls in wg0 (Wants=), waits for the oneshot (After=)
aohp unit oc log openclaw-gateway -n 200
aohp timer oc list
aohp unit oc env-start | env-stop | daemon-reload
```

## Writing a unit

`/etc/aohp/system/myagent.service`:

```ini
[Unit]
Description=My agent
After=openclaw-gateway.service
Wants=openclaw-gateway.service

[Service]
Type=simple
WorkingDirectory=/root/myagent
EnvironmentFile=-/root/myagent/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=3
TimeoutStopSec=20

[Install]
WantedBy=aohp.target
```

then `systemctl daemon-reload && systemctl enable --now myagent`. Exec lines run as `/bin/sh -c`
(root, own process group, stdout+stderr to the unit log; `$MAINPID` set for ExecStop/ExecReload).
Unknown keys only warn (`systemctl status` shows them); `Type=notify/forking`, `User=`, socket
activation and calendar specs outside `minutely|hourly|daily|weekly|*-*-* HH:MM:SS` are rejected.

Timers: `[Timer] OnBootSec= OnUnitActiveSec= OnCalendar= Unit= Persistent=` — `OnBootSec` counts
from env start, `Persistent=yes` fires a missed calendar run at the next env start. Timers are not
persistent across an env stop otherwise.

## Migrating an env that predates units

`aohp-update` (or `bash /opt/aohp-agents/install/units.sh`) installs the unit files and shims into
an existing env and enables `openclaw-gateway.service`. If the gateway was started by the 0.3.0
Driver's "Start" button / `aohp sandbox svc-start -i openclaw-gateway`, nothing else changes: on the
new ROM `startService(openclaw-gateway)` runs the unit file of that name, so the same button now
starts the supervised unit. Hand-started `sshd`/`wg-quick` (the Pixel 6 setup): `systemctl enable
--now wg0 sshd net-watchdog.timer`, then kill the hand-started processes once (or just reboot the
phone — Autostart brings the units up).
