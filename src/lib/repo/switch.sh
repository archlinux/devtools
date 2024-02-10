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

		Switch a package source repository to a specified version, tag or
		branch. The working tree and the index are updated to match the
		specified ref.

		If a version identifier is specified in the pacman version format, that
		identifier is automatically translated to the Git tag name accordingly.

		The current working directory is used if no PKGBASE is specified.

		OPTIONS
		    --discard-changes   Discard changes if index or working tree is dirty
		    -f, --force         An alias for --discard-changes
		    -h, --help          Show this help text

		EXAMPLES
		    $ ${COMMAND} 1.14.6-1 gopass gopass-jsonapi
		    $ ${COMMAND} --force 2:1.19.5-1
		    $ ${COMMAND} main
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
	local GIT_CHECKOUT_OPTIONS=()
	local paths path realpath pkgbase

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_switch_usage
				exit 0
				;;
			-f|--force|--discard-changes)
				GIT_CHECKOUT_OPTIONS+=("--force")
				shift
				;;
			--)
				shift
				break
				;;
			-*)
				# - is special to switch back to previous version
				if [[ $1 != - ]]; then
					die "invalid argument: %s" "$1"
				fi
				;;&
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
		# resolve symlink for basename
		if ! realpath=$(realpath --canonicalize-existing -- "${path}"); then
			die "No such directory: ${path}"
		fi
		# skip paths that are not directories
		if [[ ! -d "${realpath}" ]]; then
			continue
		fi
		# skip paths that are not git repositories
		if [[ ! -d "${realpath}/.git" ]]; then
			error "Not a Git repository: ${path}"
			continue
		fi

		pkgbase=$(basename "${realpath}")
		if ! git -C "${path}" checkout "${GIT_CHECKOUT_OPTIONS[@]}" "${GIT_REF}"; then
			die "Failed to switch ${pkgbase} to version ${VERSION}"
		fi
		msg "Successfully switched ${pkgbase} to version ${VERSION}"
	done
}
