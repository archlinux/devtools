#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_VERSION_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

source /usr/share/makepkg/util/message.sh

set -e


pkgctl_version_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
    cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS]

		Shows the current version information of pkgctl

		OPTIONS
		    -h, --help    Show this help text
_EOF_
}

pkgctl_version_print() {
	cat <<- _EOF_
		pkgctl @buildtoolver@
_EOF_
}

pkgctl_version() {
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_usage
				exit 0
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done

	pkgctl_version_print
}
