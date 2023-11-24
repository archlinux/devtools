# Maintainer: Levente Polyak <anthraxx[at]archlinux[dot]org>
# Maintainer: Christian Heusel <gromit@archlinux.org>
# Contributor: Pierre Schmitz <pierre@archlinux.de>

pkgname=devtools-devel
_pkgname=devtools
epoch=1
pkgver=1.0.4.r10.g4a78f0e
pkgrel=1
pkgdesc='Tools for Arch Linux package maintainers (devel version)'
arch=('any')
license=('GPL')
url='https://gitlab.archlinux.org/archlinux/devtools'
depends=(
  arch-install-scripts
  awk
  bash
  binutils
  coreutils
  diffutils
  fakeroot
  findutils
  grep
  jq
  openssh
  parallel
  rsync
  sed
  util-linux

  breezy
  git
  mercurial
  subversion
)
makedepends=(
  asciidoctor
  shellcheck
)
optdepends=('btrfs-progs: btrfs support')

conflicts=(devtools)
provides=(devtools)
source=(test/devtools.tar.gz)

sha256sums=('SKIP')
b2sums=('SKIP')

pkgver() {
  cd ${_pkgname}
  git describe --long --abbrev=7 | sed 's/v//;s/\([^-]*-g\)/r\1/;s/-/./g'
}

build() {
  cd ${_pkgname}
  make BUILDTOOLVER="${epoch}:${pkgver}-${pkgrel}-${arch}" PREFIX=/usr
}

package() {
  cd ${_pkgname}
  make PREFIX=/usr DESTDIR="${pkgdir}" install
}

# vim: ts=2 sw=2 et:
