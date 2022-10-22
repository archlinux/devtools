#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_CONFIG_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_CONFIG_SH=1

set -e

readonly XDG_DEVTOOLS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devtools"
readonly XDG_DEVTOOLS_GITLAB_CONFIG="${XDG_DEVTOOLS_DIR}/gitlab.conf"

# default config variables
export GITLAB_TOKEN=""

load_devtools_config() {
	if [[ ! -f "${XDG_DEVTOOLS_GITLAB_CONFIG}" ]]; then
		GITLAB_TOKEN=""
		return
	fi
	GITLAB_TOKEN=$(grep GITLAB_TOKEN "${XDG_DEVTOOLS_GITLAB_CONFIG}"|cut -d= -f2|cut -d\" -f2)
}

save_devtools_config() {
	mkdir -p "${XDG_DEVTOOLS_DIR}"
	printf 'GITLAB_TOKEN="%s"\n' "${GITLAB_TOKEN}" > "${XDG_DEVTOOLS_GITLAB_CONFIG}"
}
