#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_STATE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_STATE_SH=1

set -e

readonly XDG_DEVTOOLS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devtools"

get_state_folder() {
	local foldername=$1
	local path="${XDG_DEVTOOLS_STATE_DIR}/${foldername}"

	mkdir --parents -- "$path"
	printf '%s' "${path}"
}
