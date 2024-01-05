#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_PKGBUILD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_PKGBUILD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

source /usr/share/makepkg/util/message.sh

set -e


# set the pkgver variable in a PKGBUILD
# assumes that the pkgbuild is sourced to detect the presence of a pkgver function
pkgbuild_set_pkgver() {
	local new_pkgver=$1
	local pkgver=${pkgver}

	if [[ $(type -t pkgver) == function ]]; then
		# TODO: check if die or warn, if we provide _commit _gitcommit setter maybe?
		warning 'setting pkgver variable has no effect if the PKGBUILD has a pkgver() function'
	fi

	if ! grep --extended-regexp --quiet --max-count=1 "^pkgver=${pkgver}$" PKGBUILD; then
		die "Non-standard pkgver declaration"
	fi
	sed --regexp-extended "s|^(pkgver=)${pkgver}$|\1${new_pkgver}|g" --in-place PKGBUILD
}

# set the pkgrel variable in a PKGBUILD
# assumes that the pkgbuild is sourced so pkgrel is present
pkgbuild_set_pkgrel() {
	local new_pkgrel=$1
	local pkgrel=${pkgrel}

	if ! grep --extended-regexp --quiet --max-count=1 "^pkgrel=${pkgrel}$" PKGBUILD; then
		die "Non-standard pkgrel declaration"
	fi
	sed --regexp-extended "s|^(pkgrel=)${pkgrel}$|\1${new_pkgrel}|g" --in-place PKGBUILD
}

