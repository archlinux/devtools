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
	local repo=${1:-multilib}

	mkdir -p "${_DEVTOOLS_PACMAN_CACHE_DIR}"
	msg "Updating pacman database cache"
	lock 10 "${_DEVTOOLS_PACMAN_CACHE_DIR}.lock" "Locking pacman database cache"
	fakeroot -- pacman --config "${_DEVTOOLS_PACMAN_CONF_DIR}/${repo}.conf" \
		--dbpath "${_DEVTOOLS_PACMAN_CACHE_DIR}" \
		-Sy
	lock_close 10
}

get_pacman_repo_from_pkgbuild() {
	local path=${1:-PKGBUILD}
	local repo=${2:-multilib}

	# shellcheck source=contrib/makepkg/PKGBUILD.proto
	mapfile -t pkgnames < <(source "${path}"; printf "%s\n" "${pkgname[@]}")

	if (( ${#pkgnames[@]} == 0 )); then
		die 'Failed to get pkgname from %s' "${path}"
		return
	fi

	# update the pacman repo cache if it doesn't exist yet
	if [[ ! -d "${_DEVTOOLS_PACMAN_CACHE_DIR}" ]]; then
		update_pacman_repo_cache "${repo}"
	fi

	slock 10 "${_DEVTOOLS_PACMAN_CACHE_DIR}.lock" "Locking pacman database cache"
	# query repo of passed pkgname, specify --nodeps twice to skip all dependency checks
	mapfile -t repos < <(pacman --config "${_DEVTOOLS_PACMAN_CONF_DIR}/${repo}.conf" \
		--dbpath "${_DEVTOOLS_PACMAN_CACHE_DIR}" \
		--sync \
		--nodeps \
		--nodeps \
		--print \
		--print-format '%n %r' \
		"${pkgnames[0]}" 2>/dev/null | awk '$1=="'"${pkgnames[0]}"'"{print $2}'
	)
	lock_close 10

	printf "%s" "${repos[0]}"
}

get_pkgnames_from_repo_pkgbase() {
	local repo=$1
	shift
	local pkgbases=("$@")

	# update the pacman repo cache if it doesn't exist yet
	if [[ ! -d "${_DEVTOOLS_PACMAN_CACHE_DIR}" ]]; then
		update_pacman_repo_cache universe
	fi

	slock 10 "${_DEVTOOLS_PACMAN_CACHE_DIR}.lock" "Locking pacman database cache"
	# query pkgnames of passed pkgbase inside a repo
	mapfile -t pkgnames < <(expac --config <(sed "s|#DBPath.*|DBPath = $(realpath "${_DEVTOOLS_PACMAN_CACHE_DIR}")|" < "${_DEVTOOLS_PACMAN_CONF_DIR}/universe.conf") \
		--sync '%r %e %n' 2>/dev/null \
		| sort | awk -v pkgbase="${pkgbases[*]}" \
			'BEGIN { split(pkgbase, array); for (item in array) filter[array[item]]=1 } $1=="'"${repo}"'" && $2 in filter {print $3}'
	)
	lock_close 10

	if (( ! ${#pkgnames[@]} )); then
		return 1
	fi

	printf "%s\n" "${pkgnames[@]}"
	return 0
}
