#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_UTIL_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_UTIL_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}


is_tty() {
	if [ ! -t 1 ] || [ -p /dev/stdout ]; then
		return 1
	fi
	if [[ $TERM == dumb ]]; then
		return 1
	fi
	return 0
}
