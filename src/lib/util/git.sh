#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_GIT_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_GIT_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh


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

git_warmup_ssh_connection() {
	msg 'Establishing ssh connection to git@%s' "${GITLAB_HOST}"
	if ! ssh -T "git@${GITLAB_HOST}" >/dev/null; then
		die 'Failed to establish ssh connection to git@%s' "${GITLAB_HOST}"
	fi
}
