#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_CD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_CD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

set -e


pkgctl_repo_cd_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...


		OPTIONS
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND}
_EOF_
}

pkgctl_repo_cd() {
	# options
	local pkgbase

	# variables
	local path
	local workspace

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_cd_usage
				exit 0
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				pkgbase=$1
				break
				;;
		esac
	done

	if [[ -z ${PKGCTL_OUTCMD} ]]; then
		die "setup shell"
	fi

	workspace=$(get_active_workspace_name)
	path=$(get_workspace_path_from_name "${workspace}")

	printf "builtin cd -- %s\n" "${path}/${pkgbase}" >> "${PKGCTL_OUTCMD}"
}
