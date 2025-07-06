#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_LICENSE_SETUP_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_LICENSE_SETUP_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/license/check.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/license/check.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail
shopt -s nullglob


pkgctl_license_setup_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Automate the creation of a basic REUSE configuration by analyzing the
		license array specified in the PKGBUILD file of a package.

		If no PKGBASE is specified, the command defaults to using the current
		working directory.

		OPTIONS
		    -f, --force   Overwrite existing REUSE configuration
		    -h, --help    Show this help text
		    --no-check    Do not run license check after setup

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_license_setup() {
	local pkgbases=()
	local force=0
	local run_check=1

	local path exit_code
	local checks=()

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_license_setup_usage
				exit 0
				;;
			-f|--force)
				force=1
				shift
				;;
			--no-check)
				run_check=0
				shift
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
			pkgctl_license_setup_usage
			exit 1
		fi
	fi

	exit_code=0
	for path in "${pkgbases[@]}"; do
		# skip paths that are not directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi

		pushd "${path}" >/dev/null
		if license_setup "${path}" "${force}"; then
			checks+=("${path}")
		else
			exit_code=1
		fi
		popd >/dev/null
	done

	# run checks on the setup targets
	if (( run_check )) && (( ${#checks[@]} >= 1 )); then
		echo
		echo 📡 Running checks...
		pkgctl_license_check "${checks[@]}" || true
	fi

	return "$exit_code"
}

license_setup() {
	local path=$1
	local force=$2
	local pkgbase pkgname license

	if [[ ! -f PKGBUILD ]]; then
		msg_error "${BOLD}${path}:${ALL_OFF} no PKGBUILD found"
		return 1
	fi

	# shellcheck source=contrib/makepkg/PKGBUILD.proto
	if ! . ./PKGBUILD; then
		msg_error "${BOLD}${path}:${ALL_OFF} failed to source PKGBUILD"
		return 1
	fi
	pkgbase=${pkgbase:-$pkgname}

	# setup LICENSE file
	if ! license_file_setup "${pkgbase}" "${force}"; then
		return 1
	fi

	# setup REUSE.toml
	if ! reuse_setup "${pkgbase}" "${force}" "${license[@]}"; then
		return 1
	fi
}

is_valid_license() {
	local license_name=$1
	local supported_licenses
	supported_licenses=$(reuse supported-licenses | awk '{print $1}')
	if grep --quiet "^${license_name}$" <<< "$supported_licenses"; then
		return 0
	else
		return 1
	fi
}

license_file_setup() {
	local pkgbase=$1
	local force=$2

	local license_text
	license_text=$(< "${_DEVTOOLS_LIBRARY_DIR}"/data/LICENSE)

	# Write LICENSE file, or check if it mismatches
	if (( force )) || [[ ! -f LICENSE ]]; then
		printf "%s\n" "${license_text}" > LICENSE
		msg_success "${BOLD}${pkgbase}:${ALL_OFF} successfully configured LICENSE"
	elif [[ -f LICENSE ]]; then
		# if there is a license file, check whether it has the text we expect
		existing_license="$(< LICENSE)"
		if [[ "${license_text}" != "${existing_license}" ]]; then
			msg_error "${BOLD}${pkgbase}:${ALL_OFF} existing LICENSE file doesn't have expected content, use --force to overwrite"
			return 1
		fi
	fi

	# make sure the LICENSE file is found by REUSE
	mkdir --parents LICENSES
	ln --symbolic --force ../LICENSE LICENSES/0BSD.txt
}

reuse_default_annotations() {
	cat << EOF
version = 1

[[annotations]]
path = [
    "PKGBUILD",
    "README.md",
    "keys/**",
    ".SRCINFO",
    ".nvchecker.toml",
    "*.install",
    "*.sysusers",
    "*.tmpfiles",
    "*.logrotate",
    "*.pam",
    "*.service",
    "*.socket",
    "*.timer",
    "*.desktop",
    "*.hook",
]
SPDX-FileCopyrightText = "Arch Linux contributors"
SPDX-License-Identifier = "0BSD"
EOF
}

reuse_setup() {
	local pkgbase=$1
	local force=$2
	shift 2
	local license=("$@")

	# Check if REUSE.toml already exists
	if (( ! force )) && [[ -f REUSE.toml ]]; then
		msg_error "${BOLD}${pkgbase}:${ALL_OFF} REUSE.toml already exists, use --force to overwrite"
		return 1
	fi

	reuse_default_annotations > REUSE.toml

	local warning_occurred=0
	local patches=(*.patch)
	# If there are patches and there's only a single well-known license listed in the package,
	# we can generate the annotations for the patches, otherwise we will fail to do so and warn
	# the user.
	if (( ${#patches} )); then
		# If there are multiple licenses, we can't make a good guess about which license the
		# patches should have. In case the first element contains a space, we are dealing with
		# a complex SPDX license identifier.
		if (( ${#license[@]} > 1 )) || [[ ${license[0]} =~ [[:space:]] ]]; then
			msg_warn "${BOLD}${pkgbase}:${ALL_OFF} .patch files were found but couldn't automatically guess a suitable license because PKGBUILD has multiple licenses"
			patch_annotations "${pkgbase}" "TODO-Choose-a-license" "${patches[@]}" >> REUSE.toml
			warning_occurred=1
		elif ! is_valid_license "${license[0]}"; then
			msg_warn "${BOLD}${pkgbase}:${ALL_OFF} .patch files were found but couldn't automatically guess a suitable license because the PKGBUILD license '${license[0]}' is not a recognized SPDX license"
			patch_annotations "${pkgbase}" "TODO-Choose-a-license" "${patches[@]}" >> REUSE.toml
			warning_occurred=1
		else
			patch_annotations "${pkgbase}" "${license[0]}" "${patches[@]}" >> REUSE.toml
		fi
	fi

	if (( warning_occurred )); then
		msg_warn "${BOLD}${pkgbase}:${ALL_OFF} configured REUSE but a warning occurred, manually edit and fix REUSE.toml"
		return 1
	else
		reuse download --all
		msg_success "${BOLD}${pkgbase}:${ALL_OFF} successfully configured REUSE.toml"
	fi
}

patch_annotations() {
	local pkgbase=$1
	local license_identifier=$2
	shift 2
	local patches=("$@")

	local annotations
	annotations+="\n[[annotations]]\n"
	annotations+="path = [\n"
	for patch in "${patches[@]}"; do
		annotations+="    \"$(basename "${patch}")\",\n"
	done
	annotations+="]\n"
	annotations+="SPDX-FileCopyrightText = \"${pkgbase} contributors\"\n"
	annotations+="SPDX-License-Identifier = \"${license_identifier}\""
	echo -e "${annotations}"
}
