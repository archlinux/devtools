#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_LIST_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_LIST_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/workspace/util.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/workspace/util.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_workspace_list_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS]

		TODO

		OPTIONS
		    -n, --name    Only list raw workspace names
		    -p, --path    Only list raw workspace paths
		    -l, --local   None default workspaces only
		    -h, --help    Show this help text

		EXAMPLES
_EOF_
}

pkgctl_workspace_list_check_option_group() {
	local option=$1
	local print_mode=$2
	if [[ ${print_mode} != pretty ]] && [[ ${print_mode} != "${option}" ]]; then
		die "The argument '%s' cannot be used with one or more of the other specified arguments" "${option}"
		exit 1
	fi
	return 0
}

pkgctl_workspace_list() {
	# options
	local print_mode=pretty
	local only_local=0

	# variables
	local names name path active_workspace marker packages
	local pad
	local name_len=0
	local packages_len=0
	local workspaces

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_workspace_list_usage
				exit 0
				;;
			-p|--path)
				pkgctl_workspace_list_check_option_group --path "${print_mode}"
				print_mode=path
				shift
				;;
			-n|--name)
				pkgctl_workspace_list_check_option_group --name "${print_mode}"
				print_mode=name
				shift
				;;
			-l|--local)
				only_local=1
				shift
				;;
			--)
				shift
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done

	active_workspace=$(get_active_workspace_name)
	mapfile -t names < <(get_all_workspace_names "${only_local}")

	# cache values for pretty printing
	if [[ ${print_mode} == pretty ]]; then
		declare -A workspaces
		pad=$(printf '%0.1s' " "{1..60})
		for name in "${names[@]}"; do
			echo "inter $name"
			path=$(get_workspace_path_from_name "${name}")
			packages=$(workspace_package_count "${name}")

			if (( ${#name} > name_len )); then
				name_len=${#name}
			fi
			if (( ${#packages} > packages_len )); then
				packages_len=${#packages}
			fi

			workspaces["${name}->packages"]="${packages}"
			workspaces["${name}->path"]="${path}"
		done
	fi

	for name in "${names[@]}"; do
		case ${print_mode} in
			path)
				path=$(get_workspace_path_from_name "${name}")
				printf "%s\n" "${path}"
				;;
			name)
				printf "%s\n" "${name}"
				;;
			pretty)
				marker=" "
				packages="${workspaces[${name}->packages]}"
				path="${workspaces[${name}->path]}"
				if [[ $name == "$active_workspace" ]]; then
					marker="${GREEN}${BOLD}✓${ALL_OFF}${BOLD}"
				fi
				printf '%s %s %*.*s' "${marker}" "${name}" 0 $((name_len - ${#name} )) "${pad}"
				printf ' 📦 %*.*s%s' 0 $((packages_len -  ${#packages} )) "${pad}" "${packages}"
				printf ' 📂 %s%s' "${path}" "${ALL_OFF}"
				printf "%s\n" "${ALL_OFF}"
				;;
		esac
	done
}
