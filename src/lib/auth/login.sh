#!/hint/bash
#
# This may be included with or without `set -euE`
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_AUTH_LOGIN_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_AUTH_LOGIN_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/config.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/config.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -e


pkgctl_auth_login_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS]

		Interactively authenticate with the GitLab instance.

		The minimum required scopes for the token are: 'api', 'write_repository'.

		The GitLab API token can either be stored in a plaintext file, or
		supplied via the DEVTOOLS_GITLAB_TOKEN environment variable using a
		vault, see pkgctl-auth-login(1) for details.

		OPTIONS
		    -g, --gen-access-token   Open the URL to generate a new personal access token
		    -h, --help               Show this help text

		EXAMPLES
		    $ ${COMMAND}
		    $ ${COMMAND} --gen-access-token
_EOF_
}


pkgctl_auth_login() {
	local token personal_access_token_url
	local GEN_ACESS_TOKEN=0

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_auth_login_usage
				exit 0
				;;
			-g|--gen-access-token)
				GEN_ACESS_TOKEN=1
				shift
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done

	personal_access_token_url="https://${GITLAB_HOST}/-/profile/personal_access_tokens?name=pkgctl+token&scopes=api,write_repository"

    cat <<- _EOF_
	Logging into ${BOLD}${GITLAB_HOST}${ALL_OFF}

	Tip: you can generate a Personal Access Token here ${personal_access_token_url}
	The minimum required scopes are 'api' and 'write_repository'.

	If you do not want to store the token in a plaintext file, you can abort
	the following prompt and supply the token via the DEVTOOLS_GITLAB_TOKEN
	environment variable using a vault, see pkgctl-auth-login(1) for details.
_EOF_

	if (( GEN_ACESS_TOKEN )); then
		xdg-open "${personal_access_token_url}" 2>/dev/null
	fi

	# read token from stdin
	read -s -r -p "${GREEN}?${ALL_OFF} ${BOLD}Paste your authentication token:${ALL_OFF} " token
	echo

	if [[ -z ${token} ]]; then
		msg_error "  No token provided"
		exit 1
	fi

	# check if the passed token works
	GITLAB_TOKEN="${token}"
	if ! result=$(gitlab_api_get_user); then
		printf "%s\n" "$result"
		exit 1
	fi

	msg_success "  Logged in as ${BOLD}${result}${ALL_OFF}"
	save_devtools_config
}
