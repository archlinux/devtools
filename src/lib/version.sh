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

		Package version related commands.

		COMMANDS
		    check    Check if there is a newer version availble

		OPTIONS
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} check libfoo linux libbar
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
				exit 0
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done
}
