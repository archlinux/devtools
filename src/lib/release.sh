#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_RELEASE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_RELEASE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/db/update.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/db/update.sh
# shellcheck source=src/lib/util/pacman.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pacman.sh
# shellcheck source=src/lib/valid-repos.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-repos.sh

source /usr/share/makepkg/util/util.sh

set -e


pkgctl_release_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PATH]...

		Release step to commit, tag and upload build artifacts

		Modified version controlled files will first be staged for commit,
		afterwards a Git tag matching the pkgver will be created and finally
		all build artifacts will be uploaded.

		By default the target pacman repository will be auto-detected by querying
		the repo it is currently released in. When initially adding a new package
		to the repositories, the target repo must be specified manually.

		OPTIONS
		    -m, --message MSG   Use the given <msg> as the commit message
		    -r, --repo REPO     Specify target repository for new packages not in any official repo
		    -s, --staging       Release to the staging counterpart of the auto-detected repo
		    -t, --testing       Release to the testing counterpart of the auto-detected repo
		    -u, --db-update     Automatically update the pacman database after uploading
		    -h, --help          Show this help text

		EXAMPLES
		    $ ${COMMAND}
		    $ ${COMMAND} --staging --message 'libyay 0.42 rebuild' libfoo libbar
		    $ ${COMMAND} --repo extra --db-update new-package
_EOF_
}

pkgctl_release_check_option_group() {
	local option=$1
	local repo=$2
	local testing=$3
	local staging=$4
	if [[ -n "${repo}" ]] || (( testing )) || (( staging )); then
		die "The argument '%s' cannot be used with one or more of the other specified arguments" "${option}"
		exit 1
	fi
	return 0
}

pkgctl_release() {
	if (( $# < 1 )) && [[ ! -f PKGBUILD ]]; then
		pkgctl_release_usage
		exit 1
	fi

	local MESSAGE=""
	local PKGBASES=()
	local REPO=""
	local TESTING=0
	local STAGING=0
	local DB_UPDATE=0

	local path pkgbase pkgnames repo repos

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_release_usage
				exit 0
				;;
			-m|--message)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				MESSAGE=$2
				shift 2
				;;
			-r|--repo)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgctl_release_check_option_group '--repo' "${REPO}" "${TESTING}" "${STAGING}"
				REPO=$2
				shift 2
				;;
			-s|--staging)
				pkgctl_release_check_option_group '--staging' "${REPO}" "${TESTING}" "${STAGING}"
				STAGING=1
				shift
				;;
			-t|--testing)
				pkgctl_release_check_option_group '--testing' "${REPO}" "${TESTING}" "${STAGING}"
				TESTING=1
				shift
				;;
			-u|--db-update)
				DB_UPDATE=1
				shift
				;;
			-*)
				die "invalid option: %s" "$1"
				;;
			*)
				PKGBASES+=("$@")
				break
				;;
		esac
	done

	# Resolve package from current working directory
	if (( 0 == ${#PKGBASES[@]} )); then
		PKGBASES=("$PWD")
	fi

	# Update pacman cache for auto-detection
	if [[ -z ${REPO} ]]; then
		update_pacman_repo_cache multilib
	# Check valid repos if not resolved dynamically
	elif ! in_array "${REPO}" "${DEVTOOLS_VALID_REPOS[@]}"; then
		die "Invalid repository target: %s" "${REPO}"
	fi

	for path in "${PKGBASES[@]}"; do
		pushd "${path}" >/dev/null
		pkgbase=$(basename "${path}")

		# auto-detect target repository
		if ! repo=$(get_pacman_repo_from_pkgbuild PKGBUILD); then
			die 'Failed to query pacman repo'
		fi

		# fail if an existing package specifies --repo
		if [[ -n "${repo}" ]] && [[ -n ${REPO} ]]; then
			# allow unstable to use --repo
			if [[ ${REPO} == *unstable ]]; then
				repo=${REPO}
			else
				die 'Using --repo for packages that exist in official repositories is disallowed'
			fi
		fi

		# fail if a new package does not specify --repo
		if [[ -z "${repo}" ]]; then
			if [[ -z ${REPO} ]]; then
				die 'Specify --repo for packages that do not yet exist in official repositories'
			fi
			repo=${REPO}
		fi

		if (( TESTING )); then
			repo="${repo}-testing"
		elif (( STAGING )); then
			repo="${repo}-staging"
		elif [[ $repo == core ]]; then
			repo="${repo}-testing"
		fi

		msg "Releasing ${pkgbase} to ${repo}"
		commitpkg "${repo}" "${MESSAGE}"

		unset repo
		popd >/dev/null
	done

	if (( DB_UPDATE )); then
		# shellcheck disable=2119
		pkgctl_db_update
	fi
}
