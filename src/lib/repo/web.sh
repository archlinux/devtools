#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_WEB_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_WEB_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -e


pkgctl_repo_web_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Open the packaging repository's website via xdg-open. If called with
		no arguments, open the package cloned in the current working directory.

		OPTIONS
		    --print       Print the url instead of opening it with xdg-open
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} linux
_EOF_
}

pkgctl_repo_web() {
	local pkgbases=()
	local path giturl pkgbase url
	local mode=open

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_web_usage
				exit 0
				;;
			--print)
				mode=print
				shift
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

	# Check if web mode has xdg-open
	if [[ ${mode} == open ]] && ! command -v xdg-open &>/dev/null; then
		die "The web command requires 'xdg-open'"
	fi

	# Check if used without pkgnames in a packaging directory
	if (( ! $# )); then
		path=${PWD}
		if [[ ! -d "${path}/.git" ]]; then
			die "Not a Git repository: ${path}"
		fi

		giturl=$(git -C "${path}" remote get-url origin)
		if [[ ${giturl} != *${GIT_PACKAGING_NAMESPACE}* ]]; then
			die "Not a packaging repository: ${path}"
		fi

		pkgbase=$(basename "${giturl}")
		pkgbase=${pkgbase%.git}
		pkgbases=("${pkgbase}")
	fi

	for pkgbase in "${pkgbases[@]}"; do
		pkgbase=$(basename "${pkgbase}")
		path=$(gitlab_project_name_to_path "${pkgbase}")
		url="${GIT_PACKAGING_URL_HTTPS}/${path}"
		case ${mode} in
			open)
				xdg-open "${url}"
				;;
			print)
				printf "%s\n" "${url}"
				;;
			*)
				die "Unknown mode: ${mode}"
		esac
	done
}
