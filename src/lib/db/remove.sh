#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_DB_REMOVE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_DB_REMOVE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

set -e


pkgctl_db_remove_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [REPO] [PKGBASE]...

		Remove packages from binary repositories.

		OPTIONS
		    -a, --arch    Override the architecture (disables auto-detection)
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} core-testing libfoo libbar
		    $ ${COMMAND} core --arch x86_64 libyay
_EOF_
}

pkgctl_db_remove() {
	local REPO=""
	local ARCH=any
	local PKGBASES=()

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_db_remove_usage
				exit 0
				;;
			-a|--arch)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				ARCH=$2
				shift 2
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

	# shellcheck disable=SC2029
	ssh "${PACKAGING_REPO_RELEASE_HOST}" db-remove "${REPO}" "${ARCH}" "${PKGBASES[@]}"
}
