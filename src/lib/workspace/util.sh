#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_WORKSPACE_UTIL_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_WORKSPACE_UTIL_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

source /usr/share/makepkg/util/message.sh

set -e


is_xdg_workspace() {
	local path=$1
	[[ $path != */* ]] && [[ $path != . ]]
}

get_all_workspace_names() {
	local only_local=$1
	local names=()
	local builtins=(default cwd)

	TOML=~/.local/share/cargo/bin/toml
	CONFIG=~/.config/devtools/workspace.toml

	if (( ! only_local )); then
		printf "%s\n" "${builtins[@]}"
	fi

	mapfile -t names < <(${TOML} get ${CONFIG} . | jq -r 'keys | join("\n")' | grep -v '^$')
	if (( ${#names[@]} )); then
		printf "%s\n" "${names[@]}"
	fi

	echo "${#names[@]}" >&2
}

get_workspace_path_from_name() {
	local name=$1
	local path

	TOML=~/.local/share/cargo/bin/toml
	CONFIG=~/.config/devtools/workspace.toml

	case $name in
		cwd)
			path="${PWD}"
			;;
		default)
			path=$name
			;;
		*)
			if ! path="$(${TOML} get --raw ${CONFIG} -- "${name}.path")"; then
				error "unknown workspace name: %s" "${name}"
				return 1
			fi
			;;
	esac

	get_absolute_workspace_path "${path}"
}

get_absolute_workspace_path() {
	local path=$1

	# TODO XDG detection
	XDG_PKGCTL_WORKSPACES=~/.local/state/pkgctl/workspace

	if is_xdg_workspace "${path}"; then
		printf "%s/%s" "${XDG_PKGCTL_WORKSPACES}" "${path}"
		return
	fi

	if [[ $path == . ]]; then
		printf "%s" "${PWD}"
		return
	fi

	printf "%s" "${path}"
}

get_active_workspace_name() {
	local workspace
	if [[ -n ${PKGCTL_WORKSPACE} ]]; then
		workspace="${PKGCTL_WORKSPACE}"
	else
		workspace=$(get_current_workspace_name)
	fi

	printf "%s" "${workspace}"
}

get_current_workspace_name() {
	TOML=~/.local/share/cargo/bin/toml
	CONFIG=~/.config/devtools/config.toml

	DEFAULT_WORKSPACE=default
	if ! workspace=$(${TOML} get --raw ${CONFIG} -- pkgctl.workspace); then
		workspace=${DEFAULT_WORKSPACE}
	fi

	printf "%s" "${workspace}"
}

# TODO: name should reflect absolute?
get_current_workspace_path() {
	:
}

set_workspace() {
	local name=$1
	local path=${2:-$name}

	TOML=~/.local/share/cargo/bin/toml
	CONFIG=~/.config/devtools/workspace.toml

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-workspace.toml.XXXXXXXXXX)

	${TOML} set "${CONFIG}" -- "${name}.path" "${path}" > "${outfile}"
	mv "${outfile}" "${CONFIG}"
}

remove_workspace() {
	local name=$1
	local path=${2:-$name}

	TOML=~/.local/share/cargo/bin/toml
	CONFIG=~/.config/devtools/workspace.toml

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-workspace.toml.XXXXXXXXXX)

	tomlq --toml-output "del(.${name})" "${CONFIG}" > "${outfile}"
	mv "${outfile}" "${CONFIG}"
}

set_current_workspace() {
	local name=$1

	TOML=~/.local/share/cargo/bin/toml
	CONFIG=~/.config/devtools/config.toml

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-workspace.toml.XXXXXXXXXX)

	${TOML} set "${CONFIG}" -- "pkgctl.workspace" "${name}" > "${outfile}"
	mv "${outfile}" "${CONFIG}"
}

# TODO: maybe by path instead?
workspace_package_count() {
	local workspace=$1

	path=$(get_workspace_path_from_name "${workspace}")

	shopt -s nullglob
	packages=("${path}/"*/PKGBUILD)

	printf "%s" "${#packages[*]}"
}

PKGCTL_START_DIR=$(pwd)
PKGCTL_WORKSPACE_ACTIVE=0
enter_workspace() {
	local path
	local workspace

	(( PKGCTL_WORKSPACE_ACTIVE )) && return

	workspace=$(get_active_workspace_name)

	path=$(get_workspace_path_from_name "${workspace}")

	msg "Entering workspace %s in %s" "${workspace}" "${path}"
	PKGCTL_WORKSPACE_ACTIVE=1
	cd "${path}"
}

leave_workspace() {
	(( ! PKGCTL_WORKSPACE_ACTIVE )) && return
	PKGCTL_WORKSPACE_ACTIVE=0
	cd "${PKGCTL_START_DIR}"
}
