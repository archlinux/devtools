#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_VERSION_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_version_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
    cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Check and manage package versions against upstream.

		COMMANDS
		    check      Compares local package versions against upstream
		    setup      Automatically detect and setup a basic nvchecker config
		    upgrade    Adjust the PKGBUILD to match the latest upstream version

		OPTIONS
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} check libfoo linux libbar
		    $ ${COMMAND} setup libfoo
_EOF_
}

pkgctl_version() {
	if (( $# < 1 )); then
		pkgctl_version_usage
		exit 0
	fi

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_usage
				exit 0
				;;
			check)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/version/check.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/check.sh
				pkgctl_version_check "$@"
				exit $?
				;;
			upgrade)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/version/upgrade.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/upgrade.sh
				pkgctl_version_upgrade "$@"
				exit $?
				;;
			setup)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/version/setup.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/setup.sh
				pkgctl_version_setup "$@"
				exit 0
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done
}
