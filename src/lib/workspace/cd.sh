#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_CD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_CD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_workspace_cd_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [NAME]

		TODO

		OPTIONS
		    -h, --help          Show this help text

		EXAMPLES
_EOF_
}

pkgctl_workspace_cd() {
	# options
	local workspace=

	# variables
	local path

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_cd_usage
				exit 0
				;;
			--)
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				workspace=$1
				shift
				break
				;;
		esac
	done

	if [[ -z ${PKGCTL_OUTCMD} ]]; then
		die "setup shell"
	fi

	if [[ -z ${workspace} ]]; then
		workspace=$(get_active_workspace_name)
	fi
	path=$(get_workspace_path_from_name "${workspace}")

	printf "builtin cd -- %s\n" "${path}" >> "${PKGCTL_OUTCMD}"
}
