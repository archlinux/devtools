#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_VIEW_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_VIEW_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

set -eo pipefail


pkgctl_issue_view_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [IID]

		This command is designed to display detailed information about a specific issue
		in Arch Linux packaging projects. It gathers and pretty prints all relevant
		data about the issue, providing a comprehensive view that includes the issue's
		description, status as well as labels and creation date.

		By default, the command operates within the current directory, but users have
		the option to specify a different package base. Additionally, users can choose
		to view the issue in a web browser for a more interactive experience.

		OPTIONS
		    -p, --package PKGBASE  Interact with <pkgbase> instead of the current directory
		    -c, --comments         Show issue comments and activities
		    -w, --web              Open issue in a browser
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} 4
		    $ ${COMMAND} --web --package linux 4
_EOF_
}

pkgctl_issue_view() {
	if (( $# < 1 )); then
		pkgctl_issue_view_usage
		exit 0
	fi

	local web=0
	local comments=0
	local pkgbase=""
	local iid=""

	local project_path

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_view_usage
				exit 0
				;;
			-p|--package)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgbase=$2
				shift 2
				;;
			-w|--web)
				web=1
				shift
				;;
			-c|--comments)
				comments=1
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				iid=$1
				shift
				;;
		esac
	done

	if [[ -z ${iid} ]]; then
		die "missing issue iid argument"
	fi

	if [[ -z ${pkgbase} ]]; then
		if ! [[ -f PKGBUILD ]]; then
			die "missing --package option or PKGBUILD in current directory"
		fi
		pkgbase=$(realpath --canonicalize-existing .)
	fi
	pkgbase=$(basename "${pkgbase}")

	project_path=$(gitlab_project_name_to_path "${pkgbase}")

	if ! result=$(gitlab_project_issue "${pkgbase}" "${iid}"); then
		die "Failed to view issue ${pkgbase} #${iid}"
	fi

	{ read -r iid; read -r title; read -r state; read -r created_at; read -r closed_at; read -r author; } < <(
		jq --raw-output ".iid, .title, .state, .created_at, .closed_at, .author.username" <<< "${result}"
	)
	{ read -r upvotes; read -r downvotes; read -r user_notes_count; read -r confidential; } < <(
		jq --raw-output ".upvotes, .downvotes, .user_notes_count, .confidential" <<< "${result}"
	)
	description=$(jq --raw-output ".description" <<< "${result}")
	mapfile -t labels < <(
		jq --raw-output ".labels[]" <<< "${result}"
	)
	mapfile -t assignees < <(
		jq --raw-output ".assignees[].username" <<< "${result}"
	)
	if [[ ${closed_at} != null ]]; then
		closed_by=$(jq --raw-output ".closed_by.username" <<< "${result}")
	fi

	issue_url="${GIT_PACKAGING_URL_HTTPS}/${project_path}/-/issues/${iid}"
	if (( web )); then
		if ! command -v xdg-open &>/dev/null; then
			die "The web option requires 'xdg-open'"
		fi
		echo "Opening ${issue_url} in your browser."
		xdg-open "${issue_url}"
		return
	fi

	severity="$(gitlab_severity_from_labels "${labels[@]}")"
	severity_color="$(gitlab_severity_color "${severity}")"
	created_at=$(relative_date_unit "${created_at}")
	state_color="$(gitlab_issue_state_color "${state}")"
	state="$(gitlab_issue_state_display "${state}")"
	status="$(gitlab_issue_status_from_labels "${labels[@]}")"
	status_color="$(gitlab_issue_status_color "${status}")"

	scope="$(gitlab_scope_from_labels "${labels[@]}")"
	scope_color="$(gitlab_scope_color "${scope}")"
	scope_label=""
	if [[ ${scope} != unknown ]]; then
		scope_label="${scope_color}${scope}${ALL_OFF} ${GRAY}•${ALL_OFF} "
	fi

	resolution_label=""
	if resolution="$(gitlab_resolution_from_labels "${labels[@]}")"; then
		resolution_color="$(gitlab_resolution_color "${resolution}")"
		resolution_label="${resolution_color}${resolution}${ALL_OFF} ${GRAY}•${ALL_OFF} "
	fi

	confidential_label=""
	if [[ ${confidential} == true ]]; then
		confidential_label="${YELLOW}${PKGCTL_TERM_ICON_CONFIDENTIAL} CONFIDENTIAL${ALL_OFF} ${GRAY}•${ALL_OFF} "
	fi

	printf "%s%s • %s%s%sseverity %s • %s • %s%sopened by %s %s ago%s\n" \
		"${state_color}${state}${ALL_OFF}" "${GRAY}" "${confidential_label}" "${resolution_label}" "${severity_color}" "${severity}${ALL_OFF}${GRAY}" \
		"${status_color}${status}${ALL_OFF}${GRAY}" "${scope_label}" "${GRAY}" "${author}" "${created_at}" "${ALL_OFF}"
	printf "%s %s\n\n" "${BOLD}${title}${ALL_OFF}" "${GRAY}#${iid}${ALL_OFF}"
	printf "%s\n" "${description}" | glow
	printf "\n\n"
	printf "%s%s upvotes • %s downvotes • %s comments%s\n" "${GRAY}" "${upvotes}" "${downvotes}" "${user_notes_count}" "${ALL_OFF}"
	printf "%s %s\n" "${BOLD}Labels:${ALL_OFF}" "$(join_by ", " "${labels[@]}")"
	printf "%s %s\n" "${BOLD}Assignees:${ALL_OFF}" "$(join_by ", " "${assignees[@]}")"
	if [[ ${closed_at} != null ]]; then
		closed_at=$(relative_date_unit "${closed_at}")
		printf "%s %s %s ago\n" "${BOLD}Closed by:${ALL_OFF}" "${closed_by}" "${closed_at}"
	fi

	if (( comments )); then
		printf "\n\n"
		echo "${BOLD}Comments / Notes${ALL_OFF}"
		printf -v spaces '%*s' $(( COLUMNS - 2 )) ''
		printf '%s\n' "${spaces// /─}"
		printf "\n\n"

		status_dir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-gitlab-api.XXXXXXXXXX)
		printf "📡 Querying GitLab issue notes API..." > "${status_dir}/status"
		term_spinner_start "${status_dir}"
		if ! output=$(gitlab_project_issue_notes "${project_path}" "${iid}" "${status_dir}/status"); then
			term_spinner_stop "${status_dir}"
			msg_error "Failed to fetch comments"
			exit 1
		fi
		term_spinner_stop "${status_dir}"

		# pretty print each result
		while read -r result; do
			{ read -r created_at; read -r author; } < <(
				jq --raw-output ".created_at, .author.username" <<< "${result}"
			)
			body=$(jq --raw-output ".body" <<< "${result}")
			created_at=$(relative_date_unit "${created_at}")

			printf "%s commented%s %s ago%s\n" "${author}" "${GRAY}" "${created_at}" "${ALL_OFF}"
			echo "${body}" | glow
			echo
		done < <(jq --compact-output '.[]' <<< "${output}")

		echo "$output" > /tmp/notes.json
	fi

	echo
	printf "%sView this issue on GitLab: %s%s\n" "${GRAY}" "${issue_url}" "${ALL_OFF}"
}
