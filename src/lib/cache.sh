#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_CACHE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_CACHE_SH=1

set -e

readonly XDG_DEVTOOLS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/devtools"

get_cache_file() {
	local filename=$1
	local path="${XDG_DEVTOOLS_CACHE_DIR}/${filename}"

	mkdir --parents -- "$(dirname -- "$path")"
	if [[ ! -f ${path} ]]; then
		touch -- "${path}"
	fi

	printf '%s' "${path}"
}
