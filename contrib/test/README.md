# contrib/test — package install + boot + media-processing test

The shared, in-machine core for testing the immich `.deb`s: install immich, set up PostgreSQL the
way the [wiki](https://github.com/dionysius/immich-deb/wiki) documents, boot the services via
systemd, and run the upstream [test-assets](https://github.com/immich-app/test-assets) corpus
through the exact system libraries immich decodes with.

These scripts run **on the target machine**. Two things drive them:

- **Primary — the CI pipeline** (`.github/workflows/packaging.yml`): runs them per distro×arch
  against the **freshly-built artifacts**, gating the release.
- **Secondary — external provisioners** ([`../provisioners/`](../provisioners)): e.g. local incus
  containers, running the same scripts against the **latest published packages** from the apt repo.

**CI / throwaway only.** Provisioning installs packages and (re)creates the `immich` postgres
role/database. Never point it at a machine with real data.

## Requirements

- **systemd (PID 1).** Services are started with `systemctl` and asserted via journald — there is no
  non-systemd fallback. Incus containers and VMs provide this; a plain Docker / GitHub Actions
  job-level `container:` does **not** (its PID 1 isn't systemd).
- **root**, network access, and `git` (for `fetch-corpus.sh`).

## Scripts

| Script | Role | Purpose |
|---|---|---|
| `provision.sh {artifacts <DIR>\|apt}` | provision | Add repos (nodesource + `apt.crunchy.run/immich`, + PostgreSQL Apt repo on noble), install immich, create the DB, ensure postgres + redis are up. `artifacts <DIR>` installs the built `.deb`s; `apt` installs the latest published packages. |
| `fetch-corpus.sh [DEST]` | provision | Resolve the test-assets commit immich pins at the packaged version and shallow-fetch it (no submodule). |
| `run.sh` | test | Orchestrate the phases, apply the gating policy, report, exit non-zero on failure. |
| `boot-check.sh` | test | `systemctl start` the services, assert they become active and log their startup lines. |
| `probe.sh` | test | Read-only: thumbnail every corpus image/RAW via `vips`, extract metadata via exiftool. |

## Two stages (`run.sh --phases`)

- **boot** — every service must become active and log its expected startup lines. (every arch)
- **probe** — thumbnail the corpus. (amd64 only in CI)

## Gating policy

- **boot** — any service that fails to activate or is missing a startup log line fails the gate.
- **probe** — CORE image formats (`jpg/png/webp/gif/avif/heic`) must thumbnail and exiftool must
  work. Non-core formats (`jxl/rw2/tiff/raw`) are reported but **not** gated: their support depends
  on the distro's libjxl/libraw/ImageMagick, not on our packaging.

## Corpus pinning

The pinned corpus commit is **not** in this repo: `gbp` imports the upstream tarball, which keeps
`.gitmodules` (the URL) but drops the submodule gitlink. The pin lives in `immich-app/immich` at
tag `v<version>`, path `e2e/test-assets`. `fetch-corpus.sh` adds `immich` as a remote, does a cheap
treeless fetch of just that tag, reads the gitlink with `git ls-tree`, then shallow-fetches
test-assets at it. Override with `TEST_ASSETS_REF=main` to track latest instead.

## Run locally

Use an external provisioner — see [`../provisioners/incus.sh`](../provisioners/incus.sh):

```bash
contrib/provisioners/incus.sh --distros trixie     # one distro, latest published packages
```

Or, already inside a disposable systemd container/VM, as root:

```bash
contrib/test/provision.sh apt                              # or: provision.sh artifacts ./artifacts
contrib/test/fetch-corpus.sh "$PWD/test-assets"
contrib/test/run.sh --phases boot,probe --corpus "$PWD/test-assets"
```
