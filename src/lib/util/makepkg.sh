#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_MAKEPKG_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_MAKEPKG_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/util/srcinfo.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/srcinfo.sh


set -e

makepkg_source_package() {
	if (( EUID != 0 )); then
		[[ -z ${WORKDIR:-} ]] && setup_workdir
		export WORKDIR DEVTOOLS_INCLUDE_COMMON_SH
		fakeroot -- bash -$- -c "source '${BASH_SOURCE[0]}' && ${FUNCNAME[0]}"
		return
	fi
	(
		export LIBMAKEPKG_LINT_PKGBUILD_SH=1
		lint_pkgbuild() { :; }

		export LIBMAKEPKG_SRCINFO_SH=1
		write_srcinfo() { print_srcinfo; }

		set +e -- -F --source
		# shellcheck source=/usr/bin/makepkg
		source "$(command -v makepkg)"
	)
}
