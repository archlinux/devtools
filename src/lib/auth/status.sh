#!/hint/bash
#
# This may be included with or without `set -euE`
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_AUTH_STATUS_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_AUTH_STATUS_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -e


pkgctl_auth_status_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS]

		Verifies and displays information about your authentication state of
		services like the GitLab instance and reports issues if any.

		OPTIONS
		    -t, --show-token   Display the auth token
		    -h, --help         Show this help text

		EXAMPLES
		    $ ${COMMAND}
		    $ ${COMMAND} --show-token
_EOF_
}

pkgctl_auth_status() {
	local SHOW_TOKEN=0
	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_auth_status_usage
				exit 0
				;;
			-t|--show-token)
				SHOW_TOKEN=1
				shift
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done

	printf "%s\n" "${BOLD}${GITLAB_HOST}${ALL_OFF}"
	# shellcheck disable=2119
	if ! username=$(gitlab_api_get_user); then
		printf "%s\n" "${username}"
		exit 1
	fi

	msg_success "  Logged in as ${BOLD}${username}${ALL_OFF}"
	if (( SHOW_TOKEN )); then
		msg_success "  Token: ${GITLAB_TOKEN}"
	else
		msg_success "  Token: **************************"
	fi
}
