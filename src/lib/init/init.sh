#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_INIT_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_INIT_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_init_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [SHELL]

		TODO
		eval "\$(pkgctl init bash)"

		OPTIONS
		    -h, --help     Show this help text

		EXAMPLES
		    $ ${COMMAND} clone libfoo linux libbar
_EOF_
}

pkgctl_init() {
	if (( $# < 1 )); then
		pkgctl_init_usage
		exit 0
	fi

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_init_usage
				exit 0
				;;
			zsh)
				cat "${_DEVTOOLS_LIBRARY_DIR}"/init.d/init.zsh
				shift
				;;
			bash)
				cat "${_DEVTOOLS_LIBRARY_DIR}"/init.d/init.bash
				shift
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
