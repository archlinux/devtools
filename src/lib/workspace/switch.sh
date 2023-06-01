#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_SWITCH_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_SWITCH_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/add.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/add.sh
# shellcheck source=src/lib/workspace/cd.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/cd.sh
# shellcheck source=src/lib/workspace/list.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/list.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_workspace_switch_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [NAME]

		TODO

		OPTIONS
		    -i, --interactive   Interactively select the workspace
		    -c, --create        Create a new workspace before switching
		    --cd                Change the working directory to the new workspace
		    -h, --help          Show this help text

		EXAMPLES
_EOF_
}

pkgctl_workspace_switch() {
	if (( $# < 1 )); then
		pkgctl_workspace_switch_usage
		exit 0
	fi

	# options
	local name=
	local path=
	local change_cwd=0
	local interactive=0
	local create=0

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_switch_usage
				exit 0
				;;
			-c|--create)
				create=1
				shift
				;;
			--cd)
				change_cwd=1
				shift
				;;
			-i|--interactive)
				interactive=1
				shift
				;;
			--)
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				if [[ -z ${name} ]]; then
					name=$1
				elif [[ -z ${path} ]]; then
					path=$1
				else
					die "invalid argument: %s" "$1"
				fi
				shift
				;;
		esac
	done

	if [[ -z ${name} ]]; then
		name=default
	fi

	if (( interactive )); then
		# TODO: check for fzf
		name=$(pkgctl_workspace_list --name | sort | \
					fzf --exit-0 --ansi --no-multi --keep-right --height=45%)
	fi

	if (( create )); then
		if ! pkgctl_workspace_add "${name}"; then
			exit 1
		fi
	fi

	if ! path=$(get_workspace_path_from_name "${name}"); then
		die 'workspace does not exist: %s' "${name}"
	fi

	if ! set_current_workspace "${name}"; then
		die 'failed to set current workspace'
	fi

	msg "Switched to workspace %s" "${name}"

	if (( change_cwd )); then
		pkgctl_workspace_cd "$@"
	fi
}
