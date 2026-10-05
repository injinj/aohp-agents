# AOHP agent-container rootfs templates

Reproducible, Dockerfile-based builds of the Linux userland that `aohp-containerd` unpacks into
`/data/aohp/envs/<env>/rootfs` on an AOHP device. Three distros, two architectures:

| template | base image | arm64 | amd64 (Cuttlefish) |
|---|---|---|---|
| `debian`  | `docker.io/library/debian:trixie-slim` (official) | yes | yes |
| `fedora`  | `registry.fedoraproject.org/fedora:44` (official, multi-arch) | yes | yes |
| `arch`    | amd64: `docker.io/library/archlinux:base-devel` (official)<br>arm64: `docker.io/menci/archlinuxarm:base-devel` (community Arch Linux ARM image, see below) | yes | yes |

Every template contains the same agent layer: official glibc Node (nodejs.org tarball, SHASUMS256-verified),
`openclaw` (npm, pinned version) behind the launcher wrapper [`install/openclaw-wrapper.sh`](../install/openclaw-wrapper.sh)
(strips the `--jitless` that containerd injects, exports `SHELL=/bin/bash`, loads secrets), the keyless default
config [`common/openclaw-default.json`](common/openclaw-default.json) as `/root/.openclaw/openclaw.json`, the AOHP
workspace ([`common/workspace/AGENTS.md`](common/workspace/AGENTS.md) + the aohp skills), the `aohp` CLI with the
`secret` subcommand (built from [injinj/aohp](https://github.com/injinj/aohp) `feat/cli-secret` in
[`aohp-cli.Dockerfile`](aohp-cli.Dockerfile)), `/opt/aohp-skills`, and this repo cloned to `/opt/aohp-agents`
(`aohp-bootstrap`, `aohp-secrets`, `aohp-update`, `age-pass` on PATH). Plus a dev toolchain: gcc/g++, make, cmake,
gdb, strace, git, python3 + pip, jq, sqlite, gh, age, curl, wget, ssh client, nano, less, zip/unzip, iproute2.

The agent layer is shared code, not copy-paste: each Dockerfile only does the distro package install and then runs
[`common/node-install.sh`](common/node-install.sh), [`common/agent-layer.sh`](common/agent-layer.sh) and
[`common/cleanup.sh`](common/cleanup.sh). `agent-layer.sh` installs OpenClaw through this repo's own
`install/openclaw.sh`, so the template and `aohp-bootstrap` on a live device install the identical wrapper.

## Constraints (from `aohp-containerd`'s `tar_gz_extract.cpp`)

- Regular files, directories, symlinks and GNU long names only. **Hardlinks and device nodes are skipped** with a
  warning, so the tar is created with `--hard-dereference` and `dev/ proc/ sys/ run/` are shipped empty
  (containerd mounts them). `build-template.sh` fails if the tar contains anything else.
- Containerd runs everything as root, has no user namespace and does no chown: the tar uses `--numeric-owner`
  with owner 0:0.
- **The whole tarball is inflated into RAM on the device.** Keep the uncompressed rootfs ≲ 1.5 GB (sizes are
  recorded in `dist/<distro>-<arch>.txt` and in the release notes).

## Build

```bash
# rootless podman (5.x) + qemu-user-static with the aarch64 binfmt registered (F flag) for arm64 builds
template/build-template.sh debian arm64        # -> template/dist/debian-arm64.tar.gz, dist/debian-arm64.txt, dist/SHA256SUMS
template/build-template.sh fedora amd64
template/build-template.sh arch   arm64
```

Knobs (env): `NODE_VERSION` (v24.21.0), `OPENCLAW_VERSION` (2026.9.6), `AOHP_AGENTS_REF` (branch of this repo
that gets cloned into the image; default `main`), `AOHP_REF`/`AOHP_REPO` (aohp CLI + skills), `FEDORA_IMAGE`,
`ARCH_ARM64_IMAGE`, `ARCH_AMD64_IMAGE`, `DIST`, `KEEP_IMAGE=1`.

The script builds the CLI image once (native platform), then `podman build --platform linux/<arch>`, then exports by
`podman mount`-ing the image inside `podman unshare` and tarring straight from it (`--hard-dereference
--numeric-owner --owner=0 --group=0`, excluding dev/proc/sys/run). An arm64 build runs under qemu; the OpenClaw
`npm install` dominates (several minutes). Expect ~3 min (amd64) / ~10 min (arm64) per template on a 32-core host.

## Test

- **Host-side smoke** (no device): `podman run --rm --platform linux/arm64 localhost/aohp-template-debian:arm64 bash -lc
  'openclaw --version; aohp --help'` (build with `KEEP_IMAGE=1`), or unpack the tarball and `podman run --rootfs`.
- **Cuttlefish / device**: push the tarball to `/data/local/aohp-templates/<distro>.tar.gz`, bind-mount that dir over
  `/system/etc/aohp/rootfs-templates` (copy the stock templates in first so they stay visible), then
  `aohp sandbox create -n t -t <distro>` and `aohp sandbox exec t "<cmd>"`. See the
  `REPORT-templates.md` test matrix in the Lineage logs for the exact commands and results (gcc hello world, package
  manager install, `openclaw gateway` + `/health`).

## Publish

```bash
gh release create templates-$(date +%Y%m%d) --repo injinj/aohp-agents --title "rootfs templates $(date +%F)" \
  --notes-file notes.md template/dist/*.tar.gz template/dist/SHA256SUMS
```
Consumers: `vendor/aohp/fetch-prebuilts.sh` in the Lineage tree downloads `debian-arm64.tar.gz` (and optionally
fedora/arch) from the latest `templates-*` release into `packages/apps/AOHPAgentDriver/rootfs/<distro>.tar.gz` with
sha256 verification; Soong `prebuilt_etc` modules `aohp-rootfs-<distro>` install them to
`/system/etc/aohp/rootfs-templates/`.

## Distro notes

- **debian**: Debian 13 trixie, glibc 2.41, gcc 14, Python 3.13, apt. The former imperative recipe
  (`/aosp/templates/build-debian-template.sh`, debootstrap) is superseded by `debian/Dockerfile`; package set,
  Node and OpenClaw versions are the same.
- **fedora**: Fedora 44, dnf5. Built with `install_weak_deps=False` and `tsflags=nodocs`. The image has no
  `rpm-plugin-selinux`/`selinux-policy`, and the Dockerfile removes them if a dependency ever drags them in, so rpm
  never tries to label files — necessary because inside the chroot the Android kernel's selinuxfs is visible while the
  loaded policy knows nothing about Fedora contexts. `/etc/selinux/config` is set to `SELINUX=disabled` if present.
- **arch**: rolling. amd64 is the official Docker library image. arm64 has no official Arch image; Arch Linux ARM is a
  separate project, consumed via `docker.io/menci/archlinuxarm` (community image rebuilt from the ALARM generic
  aarch64 tarball by GitHub Actions; not signed by Arch or ALARM — treat as third-party; alternative:
  `docker.io/lopsided/archlinux`, also community). ALARM can lag mainline Arch by days, so the arm64 and amd64
  tarballs may carry slightly different package versions (recorded in `dist/arch-<arch>.txt`). Arch's glibc is
  built with `--enable-kernel=4.4` → fine on Android 6.1/6.6 kernels; `pacman` does not use SELinux.
  `NoExtract` drops man/doc/info pages.

## Security

Nothing in `common/` is secret: `openclaw-default.json` has no API key (`gateway.auth.mode=none`, loopback bind),
the workspace is AGENTS.md only (skills are copied from the aohp repo at build time). Secrets reach the container only
through `aohp-bootstrap`/`aohp-secrets` at provisioning time.
