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
	# temporary permission fixup
	if [[ -d "${XDG_DEVTOOLS_DIR}" ]]; then
		chmod 700 "${XDG_DEVTOOLS_DIR}"
	fi
	if [[ -f "${XDG_DEVTOOLS_GITLAB_CONFIG}" ]]; then
		chmod 600 "${XDG_DEVTOOLS_GITLAB_CONFIG}"
	fi
	if [[ -n "${DEVTOOLS_GITLAB_TOKEN}" ]]; then
		GITLAB_TOKEN="${DEVTOOLS_GITLAB_TOKEN}"
		return
	fi
	if [[ -f "${XDG_DEVTOOLS_GITLAB_CONFIG}" ]]; then
		GITLAB_TOKEN=$(grep GITLAB_TOKEN "${XDG_DEVTOOLS_GITLAB_CONFIG}"|cut -d= -f2|cut -d\" -f2)
		return
	fi
	GITLAB_TOKEN=""
}

save_devtools_config() {
	# temporary permission fixup
	if [[ -d "${XDG_DEVTOOLS_DIR}" ]]; then
		chmod 700 "${XDG_DEVTOOLS_DIR}"
	fi
	if [[ -f "${XDG_DEVTOOLS_GITLAB_CONFIG}" ]]; then
		chmod 600 "${XDG_DEVTOOLS_GITLAB_CONFIG}"
	fi
	(
		umask 0077
		mkdir -p "${XDG_DEVTOOLS_DIR}"
		printf 'GITLAB_TOKEN="%s"\n' "${GITLAB_TOKEN}" > "${XDG_DEVTOOLS_GITLAB_CONFIG}"
	)
}
