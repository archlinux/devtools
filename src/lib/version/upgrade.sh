#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_VERSION_UPGRADE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_UPGRADE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/version/check.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/check.sh
# shellcheck source=src/lib/util/pkgbuild.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pkgbuild.sh

source /usr/share/makepkg/util/message.sh

set -e

pkgctl_version_upgrade_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Upgrade the PKGBUILD according to the latest available upstream version

		Uses nvchecker, a .nvchecker.toml file and the current PKGBUILD
		pkgver to check if there is a newer package version available.

		The current working directory is used if no PKGBASE is specified.

		OPTIONS
		    -h, --help          Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_version_upgrade() {
	local path upstream_version result
	local pkgbases=()

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_upgrade_usage
				exit 0
				;;
			--)
				shift
				break
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				pkgbases=("$@")
				break
				;;
		esac
	done

	if ! command -v nvchecker &>/dev/null; then
		die "The \"$_DEVTOOLS_COMMAND\" command requires 'nvchecker'"
	fi

	# Check if used without pkgbases in a packaging directory
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			pkgbases=(".")
		else
			pkgctl_version_upgrade_usage
			exit 1
		fi
	fi

	for path in "${pkgbases[@]}"; do
		pushd "${path}" >/dev/null

		if [[ ! -f "PKGBUILD" ]]; then
			die "No PKGBUILD found for ${path}"
		fi

		# reset common PKGBUILD variables
		unset pkgbase pkgname arch source pkgver pkgrel validpgpkeys
		# shellcheck source=contrib/makepkg/PKGBUILD.proto
		. ./PKGBUILD
		pkgbase=${pkgbase:-$pkgname}

		if ! upstream_version=$(get_upstream_version); then
			die "Failed to get latest upstream version for %s" "${pkgbase}"
		fi

		if ! result=$(vercmp "${upstream_version}" "${pkgver}"); then
			die "Failed to compare version %s against %s" "${upstream_version}" "${pkgver}"
		fi

		if (( result > 0 )); then
			msg_success "${BOLD}${pkgbase}${ALL_OFF}: upgrading from version ${PURPLE}${pkgver}${ALL_OFF} to ${DARK_GREEN}${upstream_version}${ALL_OFF}"

			pkgbuild_set_pkgver "${upstream_version}"
			pkgbuild_set_pkgrel 1
		fi

		popd >/dev/null
	done
}
