#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_LICENSE_CHECK_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_LICENSE_CHECK_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail

readonly PKGCTL_LICENSE_CHECK_EXIT_COMPLIANT=0
export PKGCTL_LICENSE_CHECK_EXIT_COMPLIANT
readonly PKGCTL_LICENSE_CHECK_EXIT_FAILURE=2
export PKGCTL_LICENSE_CHECK_EXIT_FAILURE


pkgctl_license_check_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Checks package licensing compliance using REUSE and also verifies
		whether a LICENSE file with the expected Arch Linux-specific 0BSD
		license text exists.

		Upon execution, it runs 'reuse lint'.

		OPTIONS
		    -h, --help   Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_license_check() {
	local pkgbases=()
	local verbose=0

	local license_text
	license_text=$(< "${_DEVTOOLS_LIBRARY_DIR}"/data/LICENSE)

	local exit_code=${PKGCTL_LICENSE_CHECK_EXIT_COMPLIANT}

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_license_check_usage
				exit 0
				;;
			--)
				shift
				break
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				pkgbases=("$@")
				break
				;;
		esac
	done

	if ! command -v reuse &>/dev/null; then
		die "The \"$_DEVTOOLS_COMMAND\" command requires the 'reuse' CLI tool"
	fi

	# Check if used without pkgbases in a packaging directory
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			pkgbases=(".")
		else
			pkgctl_license_check_usage
			exit 1
		fi
	fi

	# enable verbose mode when we only have a single item to check
	if (( ${#pkgbases[@]} == 1 )); then
		verbose=1
	fi

	for path in "${pkgbases[@]}"; do
		# skip paths that are not directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi
		pushd "${path}" >/dev/null

		if [[ ! -f PKGBUILD ]]; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} no PKGBUILD found"
			return 1
		fi

		# reset common PKGBUILD variables
		unset pkgbase

		# shellcheck source=contrib/makepkg/PKGBUILD.proto
		if ! . ./PKGBUILD; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} failed to source PKGBUILD"
			return 1
		fi
		pkgbase=${pkgbase:-$pkgname}

		if [[ ! -e LICENSE ]]; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} is missing the LICENSE file"
			return "${PKGCTL_LICENSE_CHECK_EXIT_FAILURE}"
		fi

		if [[ ! -L LICENSES/0BSD.txt ]]; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} LICENSES/0BSD should be a symlink to LICENSE but it isn't"
			return "${PKGCTL_LICENSE_CHECK_EXIT_FAILURE}"
		fi

		# Check if the local LICENSE file mismatches our expectations
		if [[ $license_text != $(< LICENSE) ]]; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} LICENSE file doesn't have the expected Arch Linux-specific license text"
			return "${PKGCTL_LICENSE_CHECK_EXIT_FAILURE}"
		fi

		# Check for REUSE compliance
		if ! reuse lint --json | jq --exit-status '.summary.compliant' &>/dev/null; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} repository is not REUSE compliant"
			exit_code=${PKGCTL_LICENSE_CHECK_EXIT_FAILURE}

			# re-execute reuse lint for human readable output
			if (( verbose )); then
				reuse lint
			fi

			popd >/dev/null
			continue
		fi

		msg_success "${BOLD}${pkgbase}:${ALL_OFF} repository is REUSE compliant"
		popd >/dev/null
	done

	# return status based on results
	return "${exit_code}"
}
