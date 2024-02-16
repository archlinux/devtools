#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_VERSION_CHECK_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_CHECK_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail


pkgctl_version_edit_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Compares the versions of packages in the local packaging repository against
		their latest upstream versions.

		Upon execution, it generates a grouped list that provides detailed insights
		into each package's status. For each package, it displays the current local
		version alongside the latest version available upstream.

		Outputs a summary of up-to-date packages, out-of-date packages, and any
		check failures.

		OPTIONS
		    -h, --help       Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_version_edit() {
	local pkgbases=()

	local path pkgbase

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_edit_usage
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

	# Check if used without pkgbases in a packaging directory
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			pkgbases=(".")
		else
			pkgctl_version_check_usage
			exit 1
		fi
	fi

	# Check if EDITOR or xdg-open are present
	if [[ -z ${EDITOR} ]] && ! command -v xdg-open &>/dev/null; then
		die "The version edit command requires either \$EDITOR or 'xdg-open'"
	fi

	for path in "${pkgbases[@]}"; do
		pushd "${path}" >/dev/null

		if [[ ! -f "PKGBUILD" ]]; then
			die "No PKGBUILD found for ${path}"
		fi

		if [[ ! -f .nvchecker.toml ]]; then
			touch .nvchecker.toml
		fi

		if [[ -n ${EDITOR} ]]; then
			"${EDITOR}" .nvchecker.toml
		else
			xdg-open .nvchecker.toml
		fi

		popd >/dev/null
	done
}
