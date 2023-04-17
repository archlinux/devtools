#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_SWITCH_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_SWITCH_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
source /usr/share/makepkg/util/message.sh

set -e


pkgctl_repo_switch_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [VERSION] [PKGBASE]...

		Switch the version of package sources

		If no PKGBASE was provided the local directory is assumed

		OPTIONS
		    -f, --force    Discard the changes if index is dirty
		    -h, --help     Show this help text

		EXAMPLES
		    $ ${COMMAND} 1.14.6-1 gopass gopass-jsonapi
		    $ ${COMMAND} --force 2:1.19.5-1
_EOF_
}

pkgctl_repo_switch() {
	if (( $# < 1 )); then
		pkgctl_repo_switch_usage
		exit 0
	fi

	# options
	local VERSION
	local GIT_REF
	local paths
	local GIT_CHECKOUT_OPTIONS=()

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_switch_usage
				exit 0
				;;
			-f|--force)
				GIT_CHECKOUT_OPTIONS+=("--force")
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
				if [[ -n ${VERSION} ]]; then
					break
				fi
				VERSION=$1
				shift
				;;
		esac
	done

	if [[ -z ${VERSION} ]]; then
		error "missing positional argument 'VERSION'"
		pkgctl_repo_switch_usage
		exit 1
	fi

	GIT_REF="$(get_tag_from_pkgver "${VERSION}")"
	paths=("$@")

	# check if invoked without any path from within a packaging repo
	if (( ${#paths[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			paths=(".")
		else
			die "Not a package repository: $(realpath -- .)"
		fi
	fi

	for path in "${paths[@]}"; do
		if ! realpath=$(realpath -e -- "${path}"); then
			die "No such directory: ${path}"
		fi
		pkgbase=$(basename "${realpath}")

		if [[ ! -d "${path}/.git" ]]; then
			error "Not a Git repository: ${path}"
			continue
		fi

		if ! git -C "${path}" checkout "${GIT_CHECKOUT_OPTIONS[@]}" "${GIT_REF}"; then
			die "Failed to switch ${pkgbase} to version ${VERSION}"
		fi
		msg "Successfully switched ${pkgbase} to version ${VERSION}"
	done
}
