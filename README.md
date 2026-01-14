# immich deb packages

Easy to install and highly configurable debian packages for running [immich](https://github.com/immich-app/immich) on your system natively without docker. It supports a simple all-in-one package as well as that any server componenent can be installed separately. Out of the box it can be installed and built on Debian stable and latest Ubuntu LTS.

## Installation

The easiest way to install immich is using the apt repository on [apt.crunchy.run/immich](https://apt.crunchy.run/immich). Installation instructions are available directly on the repository page.

For detailed installation guides, including basic and advanced setup options, see the [Installation Wiki](https://github.com/dionysius/immich-deb/wiki/Installation).

Quick all-in-one installation:

```bash
sudo apt-get install curl
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
curl -fsSL https://apt.crunchy.run/immich/install.sh | sudo bash -
sudo apt-get install immich
```

Alternatively, download prebuilt packages from the [releases section](https://github.com/dionysius/immich-deb/releases) and verify signatures with the [signing-key](signing-key.pub). Packages are automatically built in [Github Actions](https://github.com/dionysius/immich-deb/actions) for Ubuntu LTS and Debian stable (amd64 only).

## Configuration

After installation, you'll need to configure the services. For complete setup instructions including database configuration, network settings, and service management, see the [Configuration Wiki](https://github.com/dionysius/immich-deb/wiki/Configuration).

For advanced topics:

- [External Libraries](https://github.com/dionysius/immich-deb/wiki/External-Libraries) - Configure access to media outside the default directory
- [Hardware Acceleration](https://github.com/dionysius/immich-deb/wiki/Hardware-Acceleration) - GPU acceleration setup

See also the [Official Immich Documentation](https://docs.immich.app/) for user guides and features.

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

## Inspirations and Alternatives

- [immich-native](https://github.com/arter97/immich-native)
- [immich-distribution](https://snapcraft.io/immich-distribution)
