#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_PACMAN_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_PACMAN_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

set -e


readonly _DEVTOOLS_PACMAN_CACHE_DIR=${XDG_CACHE_DIR:-$HOME/.cache}/devtools/pacman/db
readonly _DEVTOOLS_PACMAN_CONF_DIR=${_DEVTOOLS_LIBRARY_DIR}/pacman.conf.d
readonly _DEVTOOLS_MAKEPKG_CONF_DIR=${_DEVTOOLS_LIBRARY_DIR}/makepkg.conf.d


update_pacman_repo_cache() {
	mkdir -p "${_DEVTOOLS_PACMAN_CACHE_DIR}"
	msg "Updating pacman database cache"
	lock 10 "${_DEVTOOLS_PACMAN_CACHE_DIR}.lock" "Locking pacman database cache"
	fakeroot -- pacman --config "${_DEVTOOLS_PACMAN_CONF_DIR}/multilib.conf" \
		--dbpath "${_DEVTOOLS_PACMAN_CACHE_DIR}" \
		-Sy
	lock_close 10
}

get_pacman_repo_from_pkgbuild() {
	local path=${1:-PKGBUILD}

	# shellcheck source=contrib/makepkg/PKGBUILD.proto
	mapfile -t pkgnames < <(source "${path}"; printf "%s\n" "${pkgname[@]}")

	if (( ${#pkgnames[@]} == 0 )); then
		die 'Failed to get pkgname from %s' "${path}"
		return
	fi

	slock 10 "${_DEVTOOLS_PACMAN_CACHE_DIR}.lock" "Locking pacman database cache"
	mapfile -t repos < <(pacman --config "${_DEVTOOLS_PACMAN_CONF_DIR}/multilib.conf" \
		--dbpath "${_DEVTOOLS_PACMAN_CACHE_DIR}" \
		-S \
		--print \
		--print-format '%n %r' \
		"${pkgnames[0]}" | grep -E "^${pkgnames[0]} " | awk '{print $2}'
	)
	lock_close 10

	printf "%s" "${repos[0]}"
}
