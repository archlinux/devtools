#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_VERSION_UPGRADE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_UPGRADE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/version/check.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/check.sh
# shellcheck source=src/lib/util/pkgbuild.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pkgbuild.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

source /usr/share/makepkg/util/message.sh

set -e

pkgctl_version_upgrade_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Streamlines the process of keeping PKGBUILD files up-to-date with the latest
		upstream versions.

		Upon execution, it automatically adjusts the PKGBUILD file, ensuring that the
		pkgver field is set to match the latest version available from the upstream
		source. In addition to updating the pkgver, this command also resets the pkgrel
		to 1 and updates checksums.

		Outputs a summary of upgraded packages, up-to-date packages, and any check
		failures.

		OPTIONS
		    --no-update-checksums  Disable computation and update of the checksums
		    -v, --verbose          Display results including up-to-date versions
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_version_upgrade() {
	local path upstream_version result
	local pkgbases=()
	local verbose=0
	local exit_code=0
	local current_item=0
	local update_checksums=1

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_upgrade_usage
				exit 0
				;;
			--no-update-checksums)
				update_checksums=0
				shift
				;;
			-v|--verbose)
				verbose=1
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

	if ! command -v nvchecker &>/dev/null; then
		die "The \"$_DEVTOOLS_COMMAND\" command requires 'nvchecker'"
	fi

	# Check if used without pkgbases in a packaging directory
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			pkgbases=(".")
		else
			pkgctl_version_upgrade_usage
			exit 1
		fi
	fi

	# enable verbose mode when we only have a single item to check
	if (( ${#pkgbases[@]} == 1 )); then
		verbose=1
	fi

	# start a terminal spinner as checking versions takes time
	status_dir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-version-check-spinner.XXXXXXXXXX)
	term_spinner_start "${status_dir}"

	for path in "${pkgbases[@]}"; do
		# skip paths that aren't directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi
		pushd "${path}" >/dev/null

		(( ++current_item ))

		if [[ ! -f "PKGBUILD" ]]; then
			result="${BOLD}${path}${ALL_OFF}: no PKGBUILD found"
			failure+=("${result}")
			popd >/dev/null
			continue
		fi

		# reset common PKGBUILD variables
		unset pkgbase pkgname arch source pkgver pkgrel validpgpkeys
		# shellcheck source=contrib/makepkg/PKGBUILD.proto
		. ./PKGBUILD
		pkgbase=${pkgbase:-$pkgname}

		# update the current terminal spinner status
		pkgctl_version_upgrade_spinner \
			"${status_dir}" \
			"${#up_to_date[@]}" \
			"${#out_of_date[@]}" \
			"${#failure[@]}" \
			"${current_item}" \
			"${#pkgbases[@]}" \
			"${pkgbase}" \
			"query latest version"

		if ! result=$(get_upstream_version); then
			result="${BOLD}${pkgbase}${ALL_OFF}: ${result}"
			failure+=("${result}")
			popd >/dev/null
			continue
		fi
		upstream_version=${result}

		if ! result=$(vercmp "${upstream_version}" "${pkgver}"); then
			result="${BOLD}${pkgbase}${ALL_OFF}: failed to compare version ${upstream_version} against ${pkgver}"
			failure+=("${result}")
			popd >/dev/null
			continue
		fi

		if (( result == 0 )); then
			result="${BOLD}${pkgbase}${ALL_OFF}: current version ${PURPLE}${pkgver}${ALL_OFF} is latest"
			up_to_date+=("${result}")
		elif (( result < 0 )); then
			result="${BOLD}${pkgbase}${ALL_OFF}: current version ${PURPLE}${pkgver}${ALL_OFF} is newer than ${DARK_GREEN}${upstream_version}${ALL_OFF}"
			up_to_date+=("${result}")
		elif (( result > 0 )); then
			result="${BOLD}${pkgbase}${ALL_OFF}: upgraded from version ${PURPLE}${pkgver}${ALL_OFF} to ${DARK_GREEN}${upstream_version}${ALL_OFF}"
			out_of_date+=("${result}")

			# change the PKGBUILD
			pkgbuild_set_pkgver "${upstream_version}"
			pkgbuild_set_pkgrel 1

			# download sources and update the checksums
			if (( update_checksums )); then
				pkgctl_version_upgrade_spinner \
					"${status_dir}" \
					"${#up_to_date[@]}" \
					"${#out_of_date[@]}" \
					"${#failure[@]}" \
					"${current_item}" \
					"${#pkgbases[@]}" \
					"${pkgbase}" \
					"updating checksums"

				if ! result=$(pkgbuild_update_checksums /dev/null); then
					result="${BOLD}${pkgbase}${ALL_OFF}: failed to update checksums for version ${DARK_GREEN}${upstream_version}${ALL_OFF}"
					failure+=("${result}")
				fi
			fi
		fi

		popd >/dev/null
	done

	# stop the terminal spinner after all checks
	term_spinner_stop "${status_dir}"

	if (( verbose )) && (( ${#up_to_date[@]} > 0 )); then
		printf "%sUp-to-date%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${up_to_date[@]}"; do
			msg_success " ${result}"
		done
	fi

	if (( ${#failure[@]} > 0 )); then
		exit_code=1
		printf "%sFailure%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${failure[@]}"; do
			msg_error " ${result}"
		done
	fi

	if (( ${#out_of_date[@]} > 0 )); then
		printf "%sUpgraded%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${out_of_date[@]}"; do
			msg_warn " ${result}"
		done
	fi

	# Show summary when processing multiple packages
	if (( ${#pkgbases[@]} > 1 )); then
		printf '%s' "${section_separator}"
		pkgctl_version_upgrade_summary \
			"${#up_to_date[@]}" \
			"${#out_of_date[@]}" \
			"${#failure[@]}"
	fi

	# return status based on results
	return "${exit_code}"
}

pkgctl_version_upgrade_summary() {
	local up_to_date_count=$1
	local out_of_date_count=$2
	local failure_count=$3

	# print nothing if all stats are zero
	if (( up_to_date_count == 0 )) && \
			(( out_of_date_count == 0 )) && \
			(( failure_count == 0 )); then
		return 0
	fi

	# print summary for all none zero stats
	printf "%sSummary%s\n" "${BOLD}${UNDERLINE}" "${ALL_OFF}"
	if (( up_to_date_count > 0 )); then
		msg_success " Up-to-date: ${BOLD}${up_to_date_count}${ALL_OFF}" 2>&1
	fi
	if (( failure_count > 0 )); then
		msg_error " Failure: ${BOLD}${failure_count}${ALL_OFF}" 2>&1
	fi
	if (( out_of_date_count > 0 )); then
		msg_warn " Upgraded: ${BOLD}${out_of_date_count}${ALL_OFF}" 2>&1
	fi
}

pkgctl_version_upgrade_spinner() {
	local status_dir=$1
	local up_to_date_count=$2
	local out_of_date_count=$3
	local failure_count=$4
	local current=$5
	local total=$6
	local pkgbase=$7
	local message=$8

	local percentage=$(( 100 * current / total ))
	local tmp_file="${status_dir}/tmp"
	local status_file="${status_dir}/status"

	# print the current summary
	pkgctl_version_upgrade_summary \
		"${up_to_date_count}" \
		"${out_of_date_count}" \
		"${failure_count}" > "${tmp_file}"

	# print the progress status
	printf "📡 %s: %s\n" \
		"${pkgbase}" "${BOLD}${message}${ALL_OFF}" >> "${tmp_file}"
	printf "⌛ Upgrading: %s/%s [%s] %%spinner%%" \
		"${BOLD}${current}" "${total}" "${percentage}%${ALL_OFF}" \
		>> "${tmp_file}"

	# swap the status file
	mv "${tmp_file}" "${status_file}"
}
