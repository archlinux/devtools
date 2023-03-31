# Devtools - development tools for Arch Linux

This repository contains tools for the Arch Linux distribution for building
and maintaining official repository packages.

## Building

When building official distro packages the `BUILDTOOLVER` needs to be set to the
exact label of the release package in order to allow to detect the exactly used
devtools version. This is required for reproducible builds to fetch the according
files like `makepkg.conf`.

```sh
BUILDTOOLVER="${pkgver}-${pkgrel}-${arch}" make all
```

## Development

For local development testing, there is a convenience wrapper for `pkgctl` that
will automatically build the project and proxy all calls to the local build directory:

```sh
./test/bin/pkgctl --help
```

## Releasing

1. bump the version in the Makefile
2. Commit everything as  ```Version $(date +"%Y%m%d")```
3. Create a new tag ```git tag -s $(date +"%Y%m%d")```
4. Push changes
5. Upload the source tarball with ```make dist upload```
6. Update the package

## Dependencies

### Runtime

- arch-install-scripts
- awk
- bash
- binutils
- coreutils
- diffutils
- findutils
- grep
- jq
- openssh
- parallel
- rsync
- sed
- util-linux

- bzr
- git
- mercurial
- subversion

### Development

- asciidoc
- make
- shellcheck

## License

Devtools is licensed under the terms of the **GPL-3.0-or-later** (see [LICENSE](LICENSE)).
