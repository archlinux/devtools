#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_REMOVE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_REMOVE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_workspace_remove_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] NAME

		TODO

		OPTIONS
		    -h, --help          Show this help text

		EXAMPLES
_EOF_
}

pkgctl_workspace_remove() {
	if (( $# < 1 )); then
		pkgctl_workspace_remove_usage
		exit 0
	fi

	# options
	local name current

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_remove_usage
				exit 0
				;;
			--)
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				name=$1
				shift
				break
				;;
		esac
	done
	
	# TODO: check current
	current=$(get_active_workspace_name)

	# TODO: check builtin default cwd

	if ! remove_workspace "${name}"; then
		die 'failed to remove workspace %s' "${name}"
	fi
}
