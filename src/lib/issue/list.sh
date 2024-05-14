#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_LIST_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_LIST_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

set -eo pipefail


pkgctl_issue_list_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]

		The pkgctl issue list command is used to list issues associated with a specific
		packaging project or the entire packaging subgroup in Arch Linux. This command
		facilitates efficient issue management by allowing users to list and filter
		issues based on various criteria.

		Results can also be displayed directly in a web browser for easier navigation
		and review.

		OPTIONS
		    -g, --group             Get issues from the whole packaging subgroup
		    -w, --web               View results in a browser
		    -h, --help              Show this help text

		FILTER
		    -A, --all               Get all issues including closed
		    -c, --closed            Get only closed issues
		    -U, --unconfirmed       Shorthand to filter by unconfirmed status label
		    --search SEARCH         Search <string> in the fields defined by --in
		    --in LOCATION           Search in title or description (default: all)
		    -l, --label NAME        Filter issue by label <name>
		    --confidentiality TYPE  Filter by confidentiality
		    --priority PRIORITY     Shorthand to filter by priority label
		    --resolution REASON     Shorthand to filter by resolution label
		    --scope SCOPE           Shorthand to filter by scope label
		    --severity SEVERITY     Shorthand to filter by severity label
		    --status STATUS         Shorthand to filter by status label
		    --assignee USERNAME     Filter issues assigned to the given username
		    --assigned-to-me        Shorthand to filter issues assigned to you
		    --author USERNAME       Filter issues authored by the given username
		    --created-by-me         Shorthand to filter issues created by you

		EXAMPLES
		    $ ${COMMAND} libfoo libbar
		    $ ${COMMAND} --group --unconfirmed
_EOF_
}

pkgctl_issue_list() {
	if (( $# < 1 )) && [[ ! -f PKGBUILD ]]; then
		pkgctl_issue_list_usage
		exit 0
	fi

	local paths path project_path params web_params label username issue_url

	local group=0
	local web=0
	local confidential=0
	local state=opened
	local request_data=""
	local search_in="all"
	local labels=()
	local assignee=
	local author=
	local scope=all
	local confidentiality=

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_list_usage
				exit 0
				;;
			-A|--all)
				state=all
				shift
				;;
			-c|--closed)
				state=closed
				shift
				;;
			-U|--unconfirmed)
				labels+=("$(status_as_gitlab_label unconfirmed)")
				shift
				;;
			-g|--group)
				group=1
				shift
				;;
			-w|--web)
				web=1
				shift
				;;
			--in)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				search_in=$2
				shift 2
				;;
			--search)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				request_data="search=$2"
				web_params+="&search=$2"
				shift 2
				;;
			-l|--label)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				labels+=("$2")
				shift 2
				;;
			--confidentiality)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				confidentiality=$2
				if ! in_array "${confidentiality}" "${DEVTOOLS_VALID_ISSUE_CONFIDENTIALITY[@]}"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				shift 2
				;;
			--priority)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! label="$(priority_as_gitlab_label "$2")"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				labels+=("$label")
				shift 2
				;;
			--resolution)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! label="$(resolution_as_gitlab_label "$2")"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				labels+=("$label")
				shift 2
				;;
			--scope)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! label="$(scope_as_gitlab_label "$2")"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				labels+=("$label")
				shift 2
				;;
			--severity)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! label="$(severity_as_gitlab_label "$2")"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				labels+=("$label")
				shift 2
				;;
			--status)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! label="$(status_as_gitlab_label "$2")"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				labels+=("$label")
				shift 2
				;;
			--assignee)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				assignee="$2"
				shift 2
				;;
			--assigned-to-me)
				scope=assigned_to_me
				shift
				;;
			--author)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				author="$2"
				shift 2
				;;
			--created-by-me)
				scope=created_by_me
				shift
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				paths=("$@")
				break
				;;
		esac
	done

	if [[ ${search_in} == all ]]; then
		search_in="title,description"
	else
		web_params+="&in=${search_in^^}"
	fi
	params+="&in=${search_in}"

	if [[ ${state} != all ]]; then
		params+="&state=${state}"
	fi
	web_params+="&state=${state}"

	if (( ${#labels} )); then
		params+="&labels=$(join_by , "${labels[@]}")"
		web_params+="&label_name[]=$(join_by "&label_name[]=" "${labels[@]}")"
	fi

	if [[ -n ${scope} ]]; then
		params+="&scope=${scope}"
		if (( web )); then
			if ! username=$(gitlab_api_get_user); then
				exit 1
			fi
			case "${scope}" in
				created_by_me) author=${username} ;;
				assigned_to_me) assignee=${username} ;;
			esac
		fi
	fi

	if [[ -n ${assignee} ]]; then
		params+="&assignee_username=${assignee}"
		web_params+="&assignee_username=${assignee}"
	fi

	if [[ -n ${author} ]]; then
		params+="&author_username=${author}"
		web_params+="&author_username=${author}"
	fi

	if [[ -n ${confidentiality} ]]; then
		if [[ ${confidentiality} == confidential ]]; then
			params+="&confidential=true"
			web_params+="&confidential=yes"
		else
			params+="&confidential=false"
			web_params+="&confidential=no"
		fi
	fi

	# check if invoked without any path from within a packaging repo
	if (( ${#paths[@]} == 0 )); then
		if [[ -f PKGBUILD ]] && (( ! group )); then
			paths=("$(realpath --canonicalize-existing .)")
		elif (( ! group )); then
			pkgctl_issue_list_usage
			exit 1
		fi
	fi

	if (( web )) && ! command -v xdg-open &>/dev/null; then
		die "The web option requires 'xdg-open'"
	fi

	local separator="	"

	for path in "${paths[@]}"; do
		# skip paths from a glob that aren't directories
		if [[ -e "${path}" ]] && [[ ! -d "${path}" ]]; then
			continue
		fi

		pkgbase=$(basename "${path}")
		project_path=$(gitlab_project_name_to_path "${pkgbase}")

		echo "${UNDERLINE}${pkgbase}${ALL_OFF}"

		if (( web )); then
			issue_url="${GIT_PACKAGING_URL_HTTPS}/${project_path}/-/issues/?${web_params}"
			echo "Opening ${issue_url} in your browser."
			xdg-open "${issue_url}"
			continue
		fi

		status_dir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-gitlab-api.XXXXXXXXXX)
		printf "📡 Querying GitLab issues API..." > "${status_dir}/status"
		term_spinner_start "${status_dir}"
		if ! output=$(gitlab_projects_issues_list "${project_path}" "${status_dir}/status" "${params}" "${request_data}"); then
			term_spinner_stop "${status_dir}"
			echo
			continue
		fi
		term_spinner_stop "${status_dir}"

		issue_count=$(jq --compact-output 'length' <<< "${output}")
		if (( issue_count == 0 )); then
			echo "No open issues match your search"
			echo
			continue
		else
			echo "Showing ${issue_count} issues that match your search"
		fi

		print_issue_list "${output}"
	done

	if (( group )); then
		if (( web )); then
			issue_url="https://${GITLAB_HOST}/groups/${GIT_PACKAGING_NAMESPACE}/-/issues/?${web_params}"
			echo "Opening ${issue_url} in your browser."
			xdg-open "${issue_url}"
			return
		fi

		status_dir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-gitlab-api.XXXXXXXXXX)
		printf "📡 Querying GitLab issues API..." > "${status_dir}/status"
		term_spinner_start "${status_dir}"
		if ! output=$(gitlab_group_issue_list "${GIT_PACKAGING_NAMESPACE_ID}" "${status_dir}/status" "${params}" "${request_data}"); then
			term_spinner_stop "${status_dir}"
			exit 1
		fi
		term_spinner_stop "${status_dir}"

		print_issue_list "${output}"
	fi
}

print_issue_list() {
	local output=$1
	local limit=${2:-100}
	local i=0
	local status_dir
	local longest_pkgname

	# limit results
	output=$(jq ".[:${limit}]" <<< "${output}")

	mapfile -t project_ids < <(
		jq --raw-output '[.[].project_id] | unique[]' <<< "${output}")

	status_dir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-gitlab-api.XXXXXXXXXX)
	printf "📡 Querying GitLab project names..." > "${status_dir}/status"
	term_spinner_start "${status_dir}"

	# read project_id to name mapping from cache
	declare -A project_name_lookup=()
	while read -r project_id project_name; do
		project_name_lookup[${project_id}]=${project_name}
	done < <(gitlab_lookup_project_names "${status_dir}/status" "${project_ids[@]}")
	longest_pkgname=$(longest_package_name_from_ids "${project_ids[@]}")

	term_spinner_stop "${status_dir}"

	result_file=$(mktemp --tmpdir="${WORKDIR}" pkgctl-issue-list.XXXXXXXXXX)
	printf "📡 Collecting issue information %%spinner%%" > "${status_dir}/status"
	term_spinner_start "${status_dir}"

	local columns="ID,Title,Scope,Status,Severity,Age"
	if (( group )); then
		columns="ID,Package,Title,Scope,Status,Severity,Age"
	fi

	# pretty print each result
	while read -r result; do
		if (( i > limit )); then
			break
		fi
		i=$(( ++i ))

		{ read -r project_id; read -r iid; read -r title; read -r state; read -r created_at; read -r confidential; } < <(
			jq --raw-output ".project_id, .iid, .title, .state, .created_at, .confidential" <<< "${result}"
		)
		mapfile -t labels < <(
			jq --raw-output ".labels[]" <<< "${result}"
		)

		pkgbase=${project_name_lookup[${project_id}]}
		created_at=$(relative_date_unit "${created_at}")
		severity="$(gitlab_severity_from_labels "${labels[@]}")"
		severity_color="$(gitlab_severity_color "${severity}")"
		state_color="$(gitlab_issue_state_color "${state}")"
		state="$(gitlab_issue_state_display "${state}")"
		status="$(gitlab_issue_status_from_labels "${labels[@]}")"
		status_color="$(gitlab_issue_status_color "${status}")"
		status="$(gitlab_issue_status_short "${status}")"
		scope="$(gitlab_scope_from_labels "${labels[@]}")"
		scope_color="$(gitlab_scope_color "${scope}")"
		scope="$(gitlab_scope_short "${scope}")"

		title_space=$(( COLUMNS - 7 - 10 - 15 - 12 - 10 ))
		if (( group )); then
			title_space=$(( title_space - longest_pkgname ))
		fi
		if [[ ${confidential} == true ]]; then
			title_space=$(( title_space - 2 ))
		fi
		title=$(trim_string "${title_space}" "${title}")
		# gum is silly and doesn't allow double quotes
		title=${title//\"/}
		if [[ ${confidential} == true ]]; then
			title="${YELLOW}${PKGCTL_TERM_ICON_CONFIDENTIAL} ${title}${ALL_OFF}"
		fi

		if (( group )); then
			printf "%s\n" "${state_color}#$iid${ALL_OFF}${separator}${BOLD}${pkgbase}${separator}${ALL_OFF}${title}${separator}${scope_color}${scope}${ALL_OFF}${separator}${status_color}${status}${separator}${severity_color}${severity}${ALL_OFF}${separator}${GRAY}${created_at}${ALL_OFF}" \
				>> "${result_file}"
		else
			printf "%s\n" "${state_color}#$iid${ALL_OFF}${separator}${title}${separator}${scope_color}${scope}${ALL_OFF}${separator}${status_color}${status}${separator}${severity_color}${severity}${ALL_OFF}${separator}${GRAY}${created_at}${ALL_OFF}" \
				>> "${result_file}"
		fi
	done < <(jq --compact-output '.[]' <<< "${output}")

	term_spinner_stop "${status_dir}"

	gum table --print --border="none" --columns="${columns}" \
		--separator="${separator}" --file "${result_file}"
}
