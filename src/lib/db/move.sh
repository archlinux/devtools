#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_DB_MOVE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_DB_MOVE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

set -e


pkgctl_db_move_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [SOURCE_REPO] [TARGET_REPO] [PKGBASE]...

		Move packages between binary repositories.

		OPTIONS
		    -h, --help         Show this help text

		EXAMPLES
		    $ ${COMMAND} extra-staging extra-testing libfoo libbar
		    $ ${COMMAND} extra core libfoo libbar
_EOF_
}

pkgctl_db_move() {
	local SOURCE_REPO=""
	local TARGET_REPO=""
	local PKGBASES=()

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_db_move_usage
				exit 0
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				break
				;;
		esac
	done

	if (( $# < 3 )); then
		pkgctl_db_move_usage
		exit 1
	fi

	SOURCE_REPO=$1
	TARGET_REPO=$2
	shift 2
	PKGBASES+=("$@")

	# shellcheck disable=SC2029
	ssh "${PACKAGING_REPO_RELEASE_HOST}" db-move "${SOURCE_REPO}" "${TARGET_REPO}" "${PKGBASES[@]}"
}
