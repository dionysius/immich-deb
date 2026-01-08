# immich deb packages

Easy to install and highly configurable debian packages for running [immich](https://github.com/immich-app/immich) on your system natively without docker. It supports a simple all-in-one package as well as that any server componenent can be installed separately. Out of the box it can be installed and built on Debian stable and latest Ubuntu LTS.

## Installation

Easiest to install is using the the apt repository on [apt.crunchy.run](https://apt.crunchy.run/immich). For the all-in-one package install the `immich` package which will install all immich components and their required dependencies. For a customized installation use `immich-server`, `immich-machine-learning`, `immich-db-reqs`, `redis-server` and `immich-cli` in any combination. immich currently requires a newer nodejs version than is available so you will need the apt repository from [nodesource](https://downloads.nodesource.com) (for `immich-server` and `immich-cli`), don't worry you'll get notified by apt if dependency requirements can't be fullfilled.

Alternatively you can download the prebuilt packages for manual installation from the [releases section](https://github.com/dionysius/immich-deb/releases) and you can verify the signatures with this [signing-key](signing-key.pub). They are automatically built in [Github Actions](https://github.com/dionysius/immich-deb/actions) for the latest Ubuntu LTS and Debian stable (only `amd64` for now).

Quick all-in-one installation commands:

```bash
sudo apt-get install curl
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
curl -fsSL curl -fsSL https://apt.crunchy.run/immich/install.sh | sudo bash -
sudo apt-get install immich
```

After installation please read **thouroughly** through the config files containing plentyful of comments and links in `/etc/immich`. You mainly need to setup credentials for between the services, adjust the listener address, and customize the services to your needs. The directory where immich will store your media by default is `/var/lib/immich/data`. Remember to keep good security and backup hygiene.

Quick setup of a postgresql user, the printed password should be set in the immich-server database settings: (Warning! This will create a superuser, but this way immich can initialize the pgvector extension and it can make backups for you.)

```bash
 password=$(openssl rand -base64 32)
 echo "generated password is: ${password}"
 echo "create role immich with login superuser password '$password';" | sudo -u postgres psql
 echo "create database immich;" | sudo -u postgres psql
 echo "grant all privileges on database immich to immich;" | sudo -u postgres psql
```

After you have set the credentials in the database settings, restart the server with:

```bash
systemctl restart immich-server.service
```

The services should be up `active (running)`, you can check the status with:

```bash
systemctl status immich-server.service
systemctl status immich-machine-learning.service
# or to see whats wrong (scroll down)
journalctl -u immich-server.service
journalctl -u immich-machine-learning.service
```

If this immich installation is on your local machine you can now navigate to `http://localhost:2283` in your browser.

To access immich from other devices on your network, update the host setting: (Warning! This will allow immich to be accessed from your entire network)

```env
IMMICH_HOST=0.0.0.0
```

Restart the service and verify it's running:

```bash
systemctl restart immich-server.service
systemctl status immich-server.service
```

You can now navigate to `http://<ip-of-your-system>:2283` from any device on your network and the immich web UI should appear.

## Advanced configuration

You can configure everything related to how the services are run through these enviroment files. Apt will notify during upgrade if it detects changes. Any changes to systemd units should be made with `systemctl edit <unit file>`. Remember to be sure what each setting you change does, keep your system safe.

While the goal is that those packages bring everything you need, the machine-learning server currently runs with [`uv`](https://docs.astral.sh/uv/) at runtime to download python (if needed) and dependencies.

...

## Build source package

This debian source package builds [immich](https://github.com/immich-app/immich) natively on your build environment. No annoying docker! It is managed with [git-buildpackage](https://wiki.debian.org/PackagingWithGit) and aims to be a pretty good quality debian source package. You can find the maintaining command summary in [debian/gbp.conf](debian/gbp.conf).

### Requirements

- Installed `git-buildpackage` from your apt
- Installed build dependencies as defined in [debian/control `Build-Depends`](debian/control) (will notify you in the build process otherwise)
  - [`mk-build-deps`](https://manpages.debian.org/testing/devscripts/mk-build-deps.1.en.html) can help you automate the installation
- If `nodejs`/`npm` is not recent enough
  - Don't forget to look into your `*-updates`/`*-backports` apt sources for newer versions
  - Use a package from [nodesource](https://github.com/nodesource/distributions/blob/master/README.md)

### Build package

- Clone with git-buildpackage: `gbp clone https://github.com/dionysius/immich-deb.git`
- Switch to the folder: `cd immich-deb`
- Build with git-buildpackage: `gbp buildpackage`
  - There are many arguments to fine-tune the build (see `gbp buildpackage --help` and `dpkg-buildpackage --help`)
  - Notable options: `-b` (binary-only, no source files), `-us` (unsigned source package), `-uc` (unsigned .buildinfo and .changes file), `--git-export-dir=<somedir>` (before building the package export the source there)

## TODOs

- automatic testing
- describe predefined dependency pgvector, upgrade to vectorcord possible

## Inspirations and Alternatives

- https://github.com/arter97/immich-native
- https://snapcraft.io/immich-distribution
