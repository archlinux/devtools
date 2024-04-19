#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_PKGBUILD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_PKGBUILD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/util/makepkg.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/makepkg.sh

source /usr/share/makepkg/util/message.sh
source /usr/share/makepkg/util/schema.sh

set -eo pipefail


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

pkgbuild_update_checksums() {
	local status_file=$1
	local builddir newbuildfile sumtypes newsums

	[[ -z ${WORKDIR:-} ]] && setup_workdir

	builddir=$(mktemp --tmpdir="${WORKDIR}" --directory update-checksums.XXXXXX)
	newbuildfile="${builddir}/PKGBUILD"

	# generate new integrity checksums
	if ! newsums=$(BUILDDIR=${builddir} makepkg_generate_integrity 2>"${status_file}"); then
		printf 'Failed to generate new checksums'
		return 1
	fi

	# early exit if no integrity checksums are needed
	if [[ -z ${newsums} ]]; then
		return 0
	fi

	# replace the integrity sums and write it to a temporary file
	sumtypes=$(IFS='|'; echo "${known_hash_algos[*]}")
	if ! awk --assign=sumtypes="${sumtypes}" --assign=newsums="${newsums}" '
		$0 ~"^[[:blank:]]*(" sumtypes ")sums(_[^=]+)?\\+?=", $0 ~ "\\)[[:blank:]]*(#.*)?$" {
			if (!w) {
				print newsums
				w++
			}
			next
		}

		1
		END { if (!w) print newsums }' PKGBUILD > "${newbuildfile}"; then
		printf 'Failed to replace the generated checksums'
		return 1
	fi

	# overwrite the original PKGBUILD while preserving permissions
	if ! cat -- "${newbuildfile}" > PKGBUILD; then
		printf "Failed to write to the PKGBUILD file"
		return 1
	fi

	return 0
}
