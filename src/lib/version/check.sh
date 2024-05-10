#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_VERSION_CHECK_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_CHECK_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail

readonly PKGCTL_VERSION_CHECK_EXIT_UP_TO_DATE=0
export PKGCTL_VERSION_CHECK_EXIT_UP_TO_DATE
readonly PKGCTL_VERSION_CHECK_EXIT_OUT_OF_DATE=2
export PKGCTL_VERSION_CHECK_EXIT_OUT_OF_DATE
readonly PKGCTL_VERSION_CHECK_EXIT_FAILURE=3
export PKGCTL_VERSION_CHECK_EXIT_FAILURE


pkgctl_version_check_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Compares the versions of packages in the local packaging repository against
		their latest upstream versions.

		Upon execution, it generates a grouped list that provides detailed insights
		into each package's status. For each package, it displays the current local
		version alongside the latest version available upstream.

		Outputs a summary of up-to-date packages, out-of-date packages, and any
		check failures.

		OPTIONS
		    -v, --verbose    Display results including up-to-date versions
		    -h, --help       Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_version_check() {
	local pkgbases=()
	local verbose=0

	local path status_file path pkgbase upstream_version result

	local up_to_date=()
	local out_of_date=()
	local failure=()
	local current_item=0
	local section_separator=''
	local exit_code=${PKGCTL_VERSION_CHECK_EXIT_UP_TO_DATE}

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_check_usage
				exit 0
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
			pkgctl_version_check_usage
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
		# skip paths that are not directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi
		pushd "${path}" >/dev/null

		# update the current terminal spinner status
		(( ++current_item ))
		pkgctl_version_check_spinner \
			"${status_dir}" \
			"${#up_to_date[@]}" \
			"${#out_of_date[@]}" \
			"${#failure[@]}" \
			"${current_item}" \
			"${#pkgbases[@]}"

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
			result="${BOLD}${pkgbase}${ALL_OFF}: upgrade from version ${PURPLE}${pkgver}${ALL_OFF} to ${DARK_GREEN}${upstream_version}${ALL_OFF}"
			out_of_date+=("${result}")
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
		exit_code=${PKGCTL_VERSION_CHECK_EXIT_FAILURE}
		printf "%sFailure%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${failure[@]}"; do
			msg_error " ${result}"
		done
	fi

	if (( ${#out_of_date[@]} > 0 )); then
		exit_code=${PKGCTL_VERSION_CHECK_EXIT_OUT_OF_DATE}
		printf "%sOut-of-date%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${out_of_date[@]}"; do
			msg_warn " ${result}"
		done
	fi

	# Show summary when processing multiple packages
	if (( ${#pkgbases[@]} > 1 )); then
		printf '%s' "${section_separator}"
		pkgctl_version_check_summary \
			"${#up_to_date[@]}" \
			"${#out_of_date[@]}" \
			"${#failure[@]}"
	fi

	# return status based on results
	return "${exit_code}"
}

get_upstream_version() {
	local config=.nvchecker.toml
	local output errors upstream_version
	local output
	local opts=()
	local keyfile="${XDG_CONFIG_HOME:-${HOME}/.config}/nvchecker/keyfile.toml"

	# check nvchecker config file
	if ! errors=$(nvchecker_check_config "${config}"); then
		printf "%s" "${errors}"
		return 1
	fi

	# populate keyfile to nvchecker opts
	if [[ -f ${keyfile} ]]; then
		opts+=(--keyfile "${keyfile}")
	fi

	if ! output=$(GIT_TERMINAL_PROMPT=0 nvchecker --file "${config}" --logger json "${opts[@]}" 2>&1 | \
			jq --raw-output 'select(.level != "debug")'); then
		printf "failed to run nvchecker: %s" "${output}"
		return 1
	fi

	if ! errors=$(nvchecker_check_error "${output}"); then
		printf "%s" "${errors}"
		return 1
	fi

	if ! upstream_version=$(jq --raw-output --exit-status '.version' <<< "${output}"); then
		printf "failed to select version from result"
		return 1
	fi

	printf "%s" "${upstream_version}"
	return 0
}

nvchecker_check_config() {
	local config=$1

	local restricted_properties=(keyfile httptoken token)
	local property

	# check if the config file exists
	if [[ ! -f ${config} ]]; then
		printf "configuration file not found: %s" "${config}"
		return 1
	fi

	# check if config contains any restricted properties like secrets
	for property in "${restricted_properties[@]}"; do
		if grep --max-count=1 --quiet "^${property}" < "${config}"; then
			printf "restricted property in %s: %s" "${config}" "${property}"
			return 1
		fi
	done

	# check if the config contains a pkgbase section
	if [[ -n ${pkgbase} ]] && ! grep --max-count=1 --extended-regexp --quiet "^\\[\"?${pkgbase//+/\\+}\"?\\]" < "${config}"; then
		printf "missing pkgbase section in %s: %s" "${config}" "${pkgbase}"
		return 1
	fi

	# check if the config contains any section other than pkgbase
	if [[ -n ${pkgbase} ]] && property=$(grep --max-count=1 --perl-regexp "^\\[(?!\"?${pkgbase//+/\\+}\"?\\]).+\\]" < "${config}"); then
		printf "non-pkgbase section not supported in %s: %s" "${config}" "${property}"
		return 1
	fi
}

nvchecker_check_error() {
	local result=$1
	local errors

	if ! errors=$(jq --raw-output --exit-status \
			'select(.level == "error") | "\(.event)" + if .error then ": \(.error)" else "" end' \
			<<< "${result}"); then
		return 0
	fi

	mapfile -t errors <<< "${errors}"
	printf "%s\n" "${errors[@]}"
	return 1
}

pkgctl_version_check_summary() {
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
		msg_warn " Out-of-date: ${BOLD}${out_of_date_count}${ALL_OFF}" 2>&1
	fi
}

pkgctl_version_check_spinner() {
	local status_dir=$1
	local up_to_date_count=$2
	local out_of_date_count=$3
	local failure_count=$4
	local current=$5
	local total=$6

	local percentage=$(( 100 * current / total ))
	local tmp_file="${status_dir}/tmp"
	local status_file="${status_dir}/status"

	# print the current summary
	pkgctl_version_check_summary \
		"${up_to_date_count}" \
		"${out_of_date_count}" \
		"${failure_count}" > "${tmp_file}"

	# print the progress status
	printf "📡 Checking: %s/%s [%s] %%spinner%%" \
		"${BOLD}${current}" "${total}" "${percentage}%${ALL_OFF}"  \
		>> "${tmp_file}"

	# swap the status file
	mv "${tmp_file}" "${status_file}"
}
