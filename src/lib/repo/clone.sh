#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_CLONE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_CLONE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/repo/configure.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/configure.sh

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_repo_clone_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Clone Git packaging repositories from the canonical namespace.

		The configure command is subsequently invoked to synchronize the distro
		specs and makepkg.conf settings. The unprivileged option can be used
		for cloning packaging repositories without SSH access using read-only
		HTTPS.

		OPTIONS
		    -m, --maintainer=NAME  Clone all packages of the named maintainer
		    -u, --unprivileged     Clone package with read-only access and without
		                           packager info as Git author
		    --universe             Clone all existing packages, useful for cache warming
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} libfoo linux libbar
		    $ ${COMMAND} --maintainer mynickname
_EOF_
}

pkgctl_repo_clone() {
	if (( $# < 1 )); then
		pkgctl_repo_clone_usage
		exit 0
	fi

	# options
	local GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_SSH}
	local CLONE_ALL=0
	local MAINTAINER=
	local CONFIGURE_OPTIONS=()
	local pkgbases

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_clone_usage
				exit 0
				;;
			-u|--unprivileged)
				GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_HTTPS}
				CONFIGURE_OPTIONS+=("$1")
				shift
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
			--universe)
				CLONE_ALL=1
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
				pkgbases=("$@")
				break
				;;
		esac
	done

	# Query packages of a maintainer
	if [[ -n ${MAINTAINER} ]]; then
		stat_busy "Query packages"
		max_pages=$(curl --silent --location --fail --retry 3 --retry-delay 3 "https://archlinux.org/packages/search/json/?sort=name&maintainer=${MAINTAINER}" | jq -r '.num_pages')
		if [[ ! ${max_pages} =~ ([[:digit:]]) ]]; then
			stat_done
			warning "found no packages for maintainer ${MAINTAINER}"
			exit 0
		fi
		mapfile -t pkgbases < <(for page in $(seq "${max_pages}"); do
			curl --silent --location --fail --retry 3 --retry-delay 3 "https://archlinux.org/packages/search/json/?sort=name&maintainer=${MAINTAINER}&page=${page}" | jq -r '.results[].pkgbase'
			stat_progress
		done | sort --unique)
		stat_done
	fi

	# Query all released packages
	if (( CLONE_ALL )); then
		stat_busy "Query all released packages"
		max_pages=$(curl --silent --location --fail --retry 3 --retry-delay 3 "https://archlinux.org/packages/search/json/?sort=name" | jq -r '.num_pages')
		if [[ ! ${max_pages} =~ ([[:digit:]]) ]]; then
			stat_done
			die "failed to query packages"
		fi
		mapfile -t pkgbases < <(for page in $(seq "${max_pages}"); do
			curl --silent --location --fail --retry 3 --retry-delay 3 "https://archlinux.org/packages/search/json/?sort=name&page=${page}" | jq -r '.results[].pkgbase'
			stat_progress
		done | sort --unique)
		stat_done
	fi

	for pkgbase in "${pkgbases[@]}"; do
		if [[ ! -d ${pkgbase} ]]; then
			msg "Cloning ${pkgbase} ..."
			remote_url="${GIT_REPO_BASE_URL}/${pkgbase}.git"
			git clone --origin origin "${remote_url}" "${pkgbase}"
		else
			warning "Skip cloning ${pkgbase}: Directory exists"
		fi

		pkgctl_repo_configure "${CONFIGURE_OPTIONS[@]}" "${pkgbase}"
	done
}
