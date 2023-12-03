#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_CLONE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_CLONE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/archweb.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/archweb.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/repo/configure.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/configure.sh
# shellcheck source=src/lib/util/git.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/git.sh

source /usr/share/makepkg/util/message.sh

set -e
set -o pipefail


pkgctl_repo_clone_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Clone Git packaging repositories from the canonical namespace.

		The configure command is subsequently invoked to synchronize the distro
		specs and makepkg.conf settings. The protocol option can be used
		for cloning packaging repositories without SSH access using read-only
		HTTPS.

		OPTIONS
		    -m, --maintainer=NAME  Clone all packages of the named maintainer
		    --protocol https       Clone the repository over https
		    --switch VERSION       Switch the current working tree to a specified version
		    --universe             Clone all existing packages, useful for cache warming
		    -j, --jobs N           Run up to N jobs in parallel (default: $(nproc))
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} libfoo linux libbar
		    $ ${COMMAND} --maintainer mynickname
		    $ ${COMMAND} --switch 1:1.0-2 libfoo
_EOF_
}

pkgctl_repo_clone() {
	if (( $# < 1 )); then
		pkgctl_repo_clone_usage
		exit 0
	fi

	# options
	local protocol=ssh
	local GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_SSH}
	local CLONE_ALL=0
	local MAINTAINER=
	local VERSION=
	local CONFIGURE_OPTIONS=()
	local jobs=
	jobs=$(nproc)

	# variables
	local command=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	local project_path

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_clone_usage
				exit 0
				;;
			--protocol=https)
				GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_HTTPS}
				protocol=https
				CONFIGURE_OPTIONS+=("$1")
				shift
				;;
			--protocol)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if [[ $2 == https ]]; then
					GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_HTTPS}
				else
					die "unsupported protocol: %s" "$2"
				fi
				protocol="$2"
				CONFIGURE_OPTIONS+=("$1" "$2")
				shift 2
				;;
			-m|--maintainer)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				MAINTAINER="$2"
				shift 2
				;;
			--maintainer=*)
				MAINTAINER="${1#*=}"
				shift
				;;
			--switch)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				# shellcheck source=src/lib/repo/switch.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/switch.sh
				VERSION="$2"
				shift 2
				;;
			--switch=*)
				# shellcheck source=src/lib/repo/switch.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/switch.sh
				VERSION="${1#*=}"
				shift
				;;
			--universe)
				CLONE_ALL=1
				shift
				;;
			-j|--jobs)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				jobs=$2
				shift 2
				;;
			--)
				shift
				break
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

	# Query packages of a maintainer
	if [[ -n ${MAINTAINER} ]]; then
		mapfile -t pkgbases < <(archweb_query_maintainer_packages "${MAINTAINER}")
		if ! wait $!; then
			die "Failed to query maintainer packages"
		fi
	fi

	# Query all released packages
	if (( CLONE_ALL )); then
		mapfile -t pkgbases < <(archweb_query_all_packages)
		if ! wait $!; then
			die "Failed to query all packages"
		fi
	fi

	# parallelization
	if [[ ${jobs} != 1 ]] && (( ${#pkgbases[@]} > 1 )); then
		# force colors in parallel if parent process is colorized
		if [[ -n ${BOLD} ]]; then
			export DEVTOOLS_COLOR=always
		fi
		# assign command options
		if [[ -n "${VERSION}" ]]; then
			command+=" --switch '${VERSION}'"
		fi

		# warm up ssh connection as it may require user input (key unlock, hostkey verification etc)
		if [[ ${protocol} == ssh ]]; then
			git_warmup_ssh_connection
		fi

		if ! parallel --bar --jobs "${jobs}" "${command}" ::: "${pkgbases[@]}"; then
			die 'Failed to clone some packages, please check the output'
			exit 1
		fi
		exit 0
	fi

	for pkgbase in "${pkgbases[@]}"; do
		if [[ ! -d ${pkgbase} ]]; then
			msg "Cloning ${pkgbase} ..."
			project_path=$(gitlab_project_name_to_path "${pkgbase}")
			remote_url="${GIT_REPO_BASE_URL}/${project_path}.git"
			if ! git clone --origin origin "${remote_url}" "${pkgbase}"; then
				die 'failed to clone %s' "${pkgbase}"
			fi
		else
			warning "Skip cloning ${pkgbase}: Directory exists"
		fi

		pkgctl_repo_configure "${CONFIGURE_OPTIONS[@]}" "${pkgbase}"

		if [[ -n "${VERSION}" ]]; then
			pkgctl_repo_switch "${VERSION}" "${pkgbase}"
		fi
	done
}
