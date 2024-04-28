#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_CLEAN_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_CLEAN_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail


pkgctl_repo_clean_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTION] [PATH]...

		Cleans the working tree by recursively removing files that are not under
		version control, starting from the current directory.

		Files unknown to Git as well as ignored files are removed. This can, for
		example, be useful to remove all build products.

		OPTIONS
		    -i, --interactive   Show what would be done and clean files interactively
		    -n, --dry-run       Don't remove anything, just show what would be done
		    -h, --help          Show this help text

		EXAMPLES
		    $ ${COMMAND} libfoo linux libbar
		    $ ${COMMAND} --interactive libfoo linux libbar
		    $ ${COMMAND} --dry-run *
_EOF_
}

pkgctl_repo_clean() {
	# options
	local git_clean_options=()
	local paths

	local path pkgbase

	while (( $# )); do
		case $1 in
			-i|--interactive)
				git_clean_options+=("$1")
				shift
				;;
			-n|--dry-run)
				git_clean_options+=("$1")
				shift
				;;
			-h|--help)
				pkgctl_repo_clean_usage
				exit 0
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
		paths=(".")
	fi

	# print message about the work chunk
	printf "🗑️ Removing untracked files from %s working trees\n" "${BOLD}${#paths[@]}${ALL_OFF}"

	for path in "${paths[@]}"; do
		# skip paths that are not directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi

		if [[ ! -f "${path}/PKGBUILD" ]]; then
			msg_error "Not a package repository: ${path}"
			continue
		fi

		if [[ ! -d "${path}/.git" ]]; then
			msg_error "Not a Git repository: ${path}"
			continue
		fi

		pkgbase=$(basename "$(realpath "${path}")")
		pkgbase=${pkgbase%.git}

		# run dry mode to see if git would clean any files
		if [[ ! $(git -C "${path}" clean -x -d --dry-run 2>&1) ]]; then
			continue
		fi

		# git clean untracked files
		msg_success "Cleaning ${BOLD}${pkgbase}${ALL_OFF}"
		if ! git -C "${path}" clean -x -d --force "${git_clean_options[@]}"; then
			msg_error "Failed to remove untracked files"
		fi
		echo
	done
}
