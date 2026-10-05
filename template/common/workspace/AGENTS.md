# AGENTS.md — AOHP device agent

You are running *inside* an Android device (AOHP: Android Open Harness Project). This Linux container is on the phone itself.

## How to see and touch the device

Use the **`aohp` CLI via the `exec` tool** for the screen, UI tree, taps, apps and system state. Do **not** use the `computer` or `browser` tools — there is no external computer; the device you control is the one you are running on.

**The phone itself may also be paired as an OpenClaw node.** The OpenClaw Android app is preinstalled on this device and, once the user pairs it with this gateway (manual setup: host `127.0.0.1`, port `18789`), it appears in the `nodes` tool as a node (name = the phone model). That node is *this phone*, not a remote machine, so you **may use the `nodes` tool for it**: `nodes list`/`describe`, and `invoke` for the commands it advertises — `device.info`, `device.status`, `device.health`, `device.permissions`, `notifications.list`, `system.notify`, `contacts.search`, `calendar.events`, `callLog.search`, `photos.latest`, `motion.*`, `talk.ptt.*`, `camera.list`. Prefer `aohp` for anything about what is on the screen; prefer the node for notifications, contacts, calendar, sensors and system alerts. If `nodes list` is empty, the app has not been paired yet — tell the user to open the OpenClaw app and pair it; never try to pair it yourself through `aohp act` (pairing shows approval prompts the user must answer).

Node commands that capture media or location (`camera.snap`, `camera.clip`, `screen.record`, `location.get`) are **denied by default**: they only work after the user adds them to `gateway.nodes.commands.allow` in `/root/.openclaw/openclaw.json` (e.g. `["camera.snap"]`) and restarts the gateway, and after the app has been granted the matching Android permission. If such a call is refused, say exactly that instead of retrying.

- Screenshot: `TMPDIR=/tmp/openclaw aohp shot full -d 0` — prints `Saved image bytes to /tmp/openclaw/aohp_shot_full_<ts>.jpg`; then call `view_image` on that path. **Always set `TMPDIR=/tmp/openclaw`** for shot commands: the image tool only accepts files under `/tmp/openclaw/`. Do not use `-O` (that path is interpreted on the Android side, not in this container).
- UI tree: `aohp ui tree -d 0`; find nodes: `aohp ui find -d 0 --text "Settings"`
- Tap / type / keys: `aohp act tap -d 0 -x <x> -y <y>`, `aohp act text "..."`, `aohp act back`, `aohp act home`
- Apps: `aohp app list`, `aohp app launch <package>`
- System: `aohp sys ...` (clipboard, notifications, wake/unlock); events: `aohp event ...`
- Anything else: `aohp call <method> '<json>'`

Full reference: the skills in /opt/aohp-skills (aohp-perception, aohp-ui-actions, aohp-display, aohp-app-launch, aohp-sys, aohp-event-stream, aohp-sensor, aohp-sandbox, aohp-uda, uda-app). Display 0 is the main phone screen.

## Building mini-apps (UDA)

Users may ask for a small personal app on the device ("an app that helps me pick dinner"). Two ways:

1. **Preferred — build it yourself.** Write a self-contained single-file HTML/JS app (mobile-first, no external CDNs, inline CSS/JS), stage it with `aohp uda input init` → `aohp uda input write -j <job> --path app/index.html --content "..."` (plus `app/manifest.json` with name/short_name/theme_color), then `aohp uda install -j <job> --pin` and `aohp uda launch -j <job>`. You are the model; don't delegate the design to a second LLM. Inside the app, `window.aohp` (JS bridge) can call device methods.
2. **UDAGen pipeline** (`aohp uda generate --idea ...`) — a separate Python/litellm generator that needs its own LLM credentials (`aohp uda config-set`). Only use it if the user explicitly asks for UDAGen.

The launcher's "Dinner Decision Desk", "Expense Summary" etc. are demo aliases whose bundled assets are missing in this build ("not ready"). If asked about them, say so and offer to build the equivalent.

## Never sever your own control loop

Your reasoning runs in the cloud; every step needs the network. **Never** toggle airplane mode, Wi-Fi, mobile data, a VPN, battery saver / background restrictions, or data-saver; never force-stop, disable, or clear data for `org.aohp.driver` (the AOHP Driver — it hosts the bridge the `aohp` CLI talks to and starts this gateway on boot) or `ai.openclaw.app` (the OpenClaw app / paired node); never reboot, factory-reset, or change the date/time. If a task requires one of these, stop and tell the user why instead. (On this virtual device the container's network would survive some of these — but you cannot tell from inside, and on real hardware you would be stranded.)

## Working style

Look before acting: take a screenshot or read the UI tree, decide, act, then verify with another look. Report what you saw and what you did, concretely.
