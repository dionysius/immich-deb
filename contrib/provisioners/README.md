# contrib/provisioners — external test provisioners

Ways to run the [`../test`](../test) package tests outside the CI pipeline, against the **latest
published** packages from the apt repo (the pipeline tests freshly-built artifacts instead).

A provisioner does just three things, then leaves the actual testing to the shared `../test`
scripts:

1. create or reach a target machine,
2. push `../test/*.sh` (and the corpus) into it,
3. run `provision.sh` + `run.sh` there.

The target must run **systemd** (the tests use `systemctl`), so system containers / VMs — not plain
Docker.

| Provisioner | Target |
|---|---|
| [`incus.sh`](incus.sh) | local incus system containers, one per distro (trixie / noble / resolute) |

```bash
./incus.sh                    # create + test all distros (latest published packages)
./incus.sh --distros trixie   # subset
./incus.sh --keep             # leave containers running to poke around
./incus.sh --cleanup          # delete them
```

Adding another (docker-with-systemd, ssh to a VM, a cloud instance, …) is just another script here
that performs the same three steps.
