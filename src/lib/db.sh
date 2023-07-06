#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_DB_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_DB_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_db_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Pacman database modification for package update, move etc

		COMMANDS
		    move      Move packages between pacman repositories
		    remove    Remove packages from pacman repositories
		    update    Update the pacman database as final release step

		OPTIONS
		    -h, --help    Show this help text

		EXAMPLES
		    $ ${COMMAND} move extra-staging extra-testing libfoo libbar
		    $ ${COMMAND} remove core-testing libfoo libbar
		    $ ${COMMAND} update
_EOF_
}

pkgctl_db() {
	if (( $# < 1 )); then
		pkgctl_db_usage
		exit 0
	fi

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_db_usage
				exit 0
				;;
			move)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/db/move.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/db/move.sh
				pkgctl_db_move "$@"
				exit 0
				;;
			remove)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/db/remove.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/db/remove.sh
				pkgctl_db_remove "$@"
				exit 0
				;;
			update)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/db/update.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/db/update.sh
				pkgctl_db_update "$@"
				exit 0
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				die "invalid command: %s" "$1"
				;;
		esac
	done
}
