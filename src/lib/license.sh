#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_LICENSE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_LICENSE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_license_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
    cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Check and manage package license compliance.

		COMMANDS
		    check      Check package license compliance
		    setup      Automatically detect and setup a basic REUSE config

		OPTIONS
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} check libfoo linux libbar
		    $ ${COMMAND} setup libfoo
_EOF_
}

pkgctl_license() {
	if (( $# < 1 )); then
		pkgctl_license_usage
		exit 0
	fi

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_license_usage
				exit 0
				;;
			check)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/license/check.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/license/check.sh
				pkgctl_license_check "$@"
				exit $?
				;;
			setup)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/license/setup.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/license/setup.sh
				pkgctl_license_setup "$@"
				exit 0
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done
}
