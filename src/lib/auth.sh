#!/hint/bash
#
# This may be included with or without `set -euE`
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_AUTH_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_AUTH_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_auth_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Authenticate with services like GitLab.

		COMMANDS
		    login    Authenticate with the GitLab instance
		    status   View authentication status

		OPTIONS
		    -h, --help     Show this help text

		EXAMPLES
		    $ ${COMMAND} login --gen-access-token
		    $ ${COMMAND} status
_EOF_
}

pkgctl_auth() {
	if (( $# < 1 )); then
		pkgctl_auth_usage
		exit 0
	fi

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_auth_usage
				exit 0
				;;
			login)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/auth/login.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/auth/login.sh
				pkgctl_auth_login "$@"
				exit 0
				;;
			status)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/auth/status.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/auth/status.sh
				pkgctl_auth_status "$@"
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
