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
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Switch the version of package sources
		If no PKGBASE was provided the local directory is assumed

		OPTIONS
		    --version=VERSION  Set the PKGBASEs to the specified version
		    --force            Discard the changes if index is dirty
		    -h, --help         Show this help text

		EXAMPLES
		    $ ${COMMAND} --version="1.14.6-1" gopass gopass-jsonapi
		    $ ${COMMAND} --force --version="2:1.19.5-1"
_EOF_
}

pkgctl_repo_switch() {
	if (( $# < 1 )); then
		pkgctl_repo_switch_usage
		exit 0
	fi

	# options
	local VERSION=
	local GITVERSION=
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
			--version=*)
				VERSION="${1#*=}"
				GITVERSION="$(get_tag_from_pkgver "$VERSION")"
				GIT_CHECKOUT_OPTIONS+=("--detach" "${GITVERSION}")
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
				paths=("$@")
				break
				;;
		esac
	done

	# check if invoked without any path from within a packaging repo
	if (( ${#paths[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			paths=(".")
		else
			error "Not a Package repository: $(realpath .)"
			pkgctl_repo_switch_usage
			exit 1
		fi
	fi

	for path in "${paths[@]}"; do
		if ! realpath=$(realpath -e "${path}"); then
			die "No such directory: ${path}"
		fi
		pkgbase=$(basename "${realpath}")

		if [[ ! -d "${path}/.git" ]]; then
			error "Not a Git repository: ${path}"
			continue
		fi

		pushd "${path}" >/dev/null

		if [[ -n "${VERSION}" ]]; then
			if ! git show-ref --quiet "refs/tags/${GITVERSION}"; then
			   die "Failed to switch ${pkgbase} to version ${VERSION} because required tag ${GITVERSION} does not exist"
			fi
		fi

		if ! git checkout "${GIT_CHECKOUT_OPTIONS[@]}"; then
			die "Failed to switch ${pkgbase} version ${VERSION}"
		else
			msg "Successfully switched ${pkgbase} to version ${VERSION}"
		fi

		popd >/dev/null
	done
}
