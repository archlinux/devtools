#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_MACHINE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_MACHINE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh


set -eo pipefail

machine_get_hardware_name() {
	uname --machine
}

machine_has_multilib() {
	case "$(machine_get_hardware_name)" in
		x86_64*)
			return 0
			;;
	esac
	return 1
}
