#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_SHOW_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_SHOW_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_workspace_show_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [NAME]

		TODO

		OPTIONS
		    -n, --name  Print the workspace name
		    -p, --path  Print the workspace location
		    -h, --help  Show this help text

		EXAMPLES
_EOF_
}

pkgctl_workspace_show_check_option_group() {
	local option=$1
	local print_mode=$2
	if [[ ${print_mode} != pretty ]] && [[ ${print_mode} != "${option}" ]]; then
		die "The argument '%s' cannot be used with one or more of the other specified arguments" "${option}"
		exit 1
	fi
	return 0
}

pkgctl_workspace_show() {
	# options
	local print_mode=pretty
	local workspace

	# variables
	local path packages

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_show_usage
				exit 0
				;;
			-p|--path)
				pkgctl_workspace_show_check_option_group --path "${print_mode}"
				print_mode=path
				shift
				;;
			-n|--name)
				pkgctl_workspace_show_check_option_group --name "${print_mode}"
				print_mode=name
				shift
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
				;;
		esac
	done

	# use the active workspace if none is provided
	if [[ -z ${workspace} ]]; then
		workspace=$(get_active_workspace_name)
	fi

	path=$(get_workspace_path_from_name "${workspace}")
	packages=$(workspace_package_count "${workspace}")

	case ${print_mode} in
		path)
			printf "%s\n" "${path}"
			;;
		name)
			printf "%s\n" "${workspace}"
			;;
		pretty)
			msg2 "${workspace}: ${packages} packages ${path}"
			;;
	esac
}
