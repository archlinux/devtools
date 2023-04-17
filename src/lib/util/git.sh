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

git_show_ref() {
	local ref=$1
	git \
		--no-pager \
		show-ref \
		--verify \
		"${ref}"
}

git_is_branch() {
	local ref=$1
	git_show_ref "refs/heads/${ref}" &>/dev/null
}

git_is_tag() {
	local ref=$1
	git_show_ref "refs/tags/${ref}" &>/dev/null
}
