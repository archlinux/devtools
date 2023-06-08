#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_AUR_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_AUR_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -eo pipefail


pkgctl_aur_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Interact with the Arch User Repository (AUR).

		Provides a suite of tools designed for managing and interacting with the Arch
		User Repository (AUR). It simplifies various tasks related to AUR, including
		importing repositories, managing packages, and transitioning packages between
		the official repositories and the AUR.

		COMMANDS
		    drop-from-repo    Drop a package from the official repository to the AUR

		OPTIONS
		    -h, --help        Show this help text

		EXAMPLES
		    $ ${COMMAND} drop-from-repo libfoo
_EOF_
}

pkgctl_aur() {
	if (( $# < 1 )); then
		pkgctl_aur_usage
		exit 0
	fi

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_aur_usage
				exit 0
				;;
			drop-from-repo)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/aur/drop-from-repo.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/aur/drop-from-repo.sh
				pkgctl_aur_drop_from_repo "$@"
				exit 0
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				die "invalid command: %s" "$1"
				;;
		esac
	done
}
