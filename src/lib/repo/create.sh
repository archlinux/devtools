#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_CREATE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_CREATE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/repo/clone.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/clone.sh
# shellcheck source=src/lib/repo/configure.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/configure.sh

set -e


pkgctl_repo_create_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Create a new Git packaging repository in the canonical GitLab namespace.

		This command requires a valid GitLab API authentication. To setup a new
		GitLab token or check the currently configured one please consult the
		'auth' subcommand for further instructions.

		If invoked without a parameter, try to create a packaging repository
		based on the PKGBUILD from the current working directory and configure
		the local repository afterwards.

		OPTIONS
		    -c, --clone   Clone the Git repository after creation
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} libfoo
_EOF_
}

pkgctl_repo_create() {
	# options
	local pkgbases=()
	local pkgbase
	local clone=0
	local configure=0

	# variables
	local path

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_create_usage
				exit 0
				;;
			-c|--clone)
				clone=1
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				pkgbases=("$@")
				break
				;;
		esac
	done

	# check if invoked without any path from within a packaging repo
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			if ! path=$(realpath -e .); then
				die "failed to read path from current directory"
			fi
			pkgbases=("$(basename "${path}")")
			clone=0
			configure=1
		else
			pkgctl_repo_create_usage
			exit 1
		fi
	fi

	# create projects
	for pkgbase in "${pkgbases[@]}"; do
		if ! gitlab_api_create_project "${pkgbase}" >/dev/null; then
			die "failed to create project: ${pkgbase}"
		fi
		msg_success "Successfully created ${pkgbase}"
		if (( clone )); then
			pkgctl_repo_clone "${pkgbase}"
		elif (( configure )); then
			pkgctl_repo_configure
		fi
	done

	# some convenience hints if not in auto clone/configure mode
	if (( ! clone )) && (( ! configure )); then
		cat <<- _EOF_

		For new clones:
			$(msg2 "pkgctl repo clone ${pkgbases[*]}")
		For existing clones:
			$(msg2 "pkgctl repo configure ${pkgbases[*]}")
		_EOF_
	fi
}
