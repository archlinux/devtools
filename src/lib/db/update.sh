#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_DB_UPDATE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_DB_UPDATE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

set -e


pkgctl_db_update_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS]

		Update the binary repository as final release step for packages that
		have been transfered and staged on ${PACKAGING_REPO_RELEASE_HOST}.

		OPTIONS
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND}
_EOF_
}

pkgctl_db_update() {
	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_db_update_usage
				exit 0
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done

	ssh "${PACKAGING_REPO_RELEASE_HOST}" db-update
}
