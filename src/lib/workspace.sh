#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_workspace_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Manage package workspace locations and settings

		COMMANDS
		    add         Add a new workspace
		    cd          Change into the directory of the workspace
		    list, ls    List availiable workspaces
		    remove, rm  Remove a workspace
		    show        Show details about a workspace
		    switch      Switch the current worspace

		OPTIONS
		    -h, --help     Show this help text

		EXAMPLES
		    $ ${COMMAND} workspace show
		    $ ${COMMAND} workspace list
		    $ ${COMMAND} workspace add test --cd
_EOF_
}

pkgctl_workspace() {
	if (( $# < 1 )); then
		pkgctl_workspace_usage
		exit 0
	fi

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_usage
				exit 0
				;;
			add)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/workspace/add.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/add.sh
				pkgctl_workspace_add "$@"
				exit 0
				;;
			cd)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/workspace/cd.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/cd.sh
				pkgctl_workspace_cd "$@"
				exit 0
				;;
			list|ls)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/workspace/list.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/list.sh
				pkgctl_workspace_list "$@"
				exit 0
				;;
			remove|rm)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/workspace/remove.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/remove.sh
				pkgctl_workspace_remove "$@"
				exit 0
				;;
			show)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/workspace/show.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/show.sh
				pkgctl_workspace_show "$@"
				exit 0
				;;
			switch)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/workspace/switch.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/switch.sh
				pkgctl_workspace_switch "$@"
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
