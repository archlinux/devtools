#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_ADD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_ADD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_workspace_add_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] NAME [PATH]

		TODO

		OPTIONS
		    -f, --force   Overwrite if the workspace already exists 
		    -s, --switch  Switch to the new workspace
		    -c, --cd      Change the current working directory
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} aur
		    $ ${COMMAND} --force foobar ~/packages
_EOF_
}

pkgctl_workspace_add() {
	if (( $# < 1 )); then
		pkgctl_workspace_add_usage
		exit 0
	fi

	# options
	local force=0
	local switch=0
	local change_cwd=0
	local name
	local path

	# variables
	local full_path

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_add_usage
				exit 0
				;;
			-c|--cd)
				# shellcheck source=src/lib/workspace/cd.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/cd.sh
				change_cwd=1
				shift
				;;
			-s|--switch)
				# shellcheck source=src/lib/workspace/switch.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/switch.sh
				switch=1
				shift
				;;
			-f|--force)
				force=1
				shift
				;;
			--)
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				if [[ -n ${name} ]]; then
					path=$1
					break;
				fi
				name=$1
				shift
				;;
		esac
	done

	# path fallback inside XDG workspace dir
	if [[ -z ${path} ]]; then
		path=${name}
	fi

	if (( ! force )) && get_workspace_path_from_name "${name}" &>/dev/null; then
		die "cannot create workspce '%s': Workspace already exists" "${name}"
	fi

	# TODO: xdg shorthand needs to be resolved into path
	# TODO: detect relative paths (no leading /)
	
	full_path=$(get_absolute_workspace_path "${path}")

	if ! mkdir -p "${full_path}"; then
		die "failed to create workspace path %s" "${full_path}"
	fi

	if ! [[ -w ${full_path} ]]; then
		die "workspace path %s is not writable" "${full_path}"
	fi

	set_workspace "${name}" "${path}"

	if (( switch )); then
		pkgctl_workspace_switch "${name}"
	fi

	if (( change_cwd )); then
		pkgctl_workspace_cd "${name}"
	fi
}
