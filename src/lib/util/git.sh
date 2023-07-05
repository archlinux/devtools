#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_GIT_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_GIT_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}


git_diff_tree() {
	local commit=$1
	local path=$2
	git \
		--no-pager \
		diff \
		--color=never \
		--color-moved=no \
		--unified=0 \
		--no-prefix \
		--no-ext-diff \
		"${commit}" \
		-- "${path}"
}

is_valid_release_branch() {
	local branch=$1
	in_array "${branch}" "${VALID_RELEASE_BRANCHES[@]}"
}
