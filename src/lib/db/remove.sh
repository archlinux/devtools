#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_DB_REMOVE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_DB_REMOVE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/util/pacman.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pacman.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh
# shellcheck source=src/lib/valid-repos.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-repos.sh

set -e


pkgctl_db_remove_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [REPO] [PKGBASE]...

		Remove packages from pacman repositories. By default passing a pkgbase removes
		all split packages, debug packages as well as entries from the state repo for
		all existing architectures.

		Beware when using the --partial option, as it may most likely lead to
		undesired effects by leaving debug packages behind as well as dangling entries
		in the state repository.

		OPTIONS
		    -a, --arch    Remove only one specific architecture (disables auto-detection)
		    --partial     Remove only partial pkgnames from a split package. This leaves
		                  debug packages behind and pkgbase entries in the state repo.
		    --noconfirm   Bypass any confirmation messages, should only be used with caution
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} core-testing libfoo libbar
		    $ ${COMMAND} --arch x86_64 core libyay
_EOF_
}

pkgctl_db_remove() {
	local REPO=""
	local PKGBASES=()
	local pkgnames=()
	local partial=0
	local confirm=1
	local dbscripts_options=()
	local lookup_repo=multilib
	local pkgname

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_db_remove_usage
				exit 0
				;;
			--partial)
				partial=1
				dbscripts_options+=(--partial)
				shift
				;;
			-a|--arch)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				dbscripts_options+=(--arch "$2")
				shift 2
				;;
			--noconfirm)
				confirm=0
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				break
				;;
		esac
	done

	if (( $# < 2 )); then
		pkgctl_db_remove_usage
		exit 1
	fi

	REPO=$1
	shift
	PKGBASES+=("$@")
	pkgnames=("${PKGBASES[@]}")

	# check if the target repo is valid
	if ! in_array "${REPO}" "${DEVTOOLS_VALID_REPOS[@]}"; then
		die "Invalid repository target: %s" "${REPO}"
	fi

	# update pacman cache to query all pkgnames
	if (( ! partial )); then
		case ${REPO} in
			*-unstable)
				update_pacman_repo_cache unstable
				;;
			*-staging)
				update_pacman_repo_cache multilib-staging
				;;
			*-testing)
				update_pacman_repo_cache multilib-testing
				;;
			*)
				update_pacman_repo_cache multilib
				;;
		esac

		# fetch the pkgnames of all pkgbase as present in the repo
		mapfile -t pkgnames < <(get_pkgnames_from_repo_pkgbase "${REPO}" "${PKGBASES[@]}")
		echo

		if (( ! ${#pkgnames[@]} )); then
			error "Packages not found in %s" "${REPO}"
			exit 1
		fi
	fi

	# print list of packages
	printf "%sRemoving packages from %s:%s\n" "${RED}" "${REPO}" "${ALL_OFF}"
	for pkgname in "${pkgnames[@]}"; do
		printf "• %s\n" "${pkgname}"
	done

	# print explenation about partial removal
	if (( partial )); then
		echo
		msg_warn "${YELLOW}Removing only partial pkgnames from a split package.${ALL_OFF}"
		msg_warn "${YELLOW}This leaves debug packages and pkgbase entries in the state repo!${ALL_OFF}"
	fi

	# ask for confirmation
	if (( confirm )); then
		echo
		if ! prompt "${GREEN}${BOLD}?${ALL_OFF} Are you sure this is correct?"; then
			exit 1
		fi
	fi

	echo
	# shellcheck disable=SC2029
	ssh "${PACKAGING_REPO_RELEASE_HOST}" db-remove "${dbscripts_options[@]}" "${REPO}" "${PKGBASES[@]}"
}
