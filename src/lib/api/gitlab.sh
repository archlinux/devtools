#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_API_GITLAB_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_API_GITLAB_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/cache.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/cache.sh
# shellcheck source=src/lib/config.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/config.sh
# shellcheck source=src/lib/valid-issue.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-issue.sh

set -e

graphql_api_call() {
	local outfile=$1
	local request=$2
	local node_type=$3
	local data=$4
	local hasNextPage cursor

	# empty token
	if [[ -z "${GITLAB_TOKEN}" ]]; then
		msg_error "  api call failed: No token provided"
		return 1
	fi

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	api_workdir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-gitlab-api.XXXXXXXXXX)

	# normalize graphql data and prepare query
	data="${data//\"/\\\"}"
	data='{
		"query": "'"${data}"'"
	}'
	data="${data//$'\t'/ }"
	data="${data//$'\n'/}"

	cursor=""
	hasNextPage=true
	while [[ ${hasNextPage} == true ]]; do
		data=$(sed -E 's|after: \\"[a-zA-Z0-9]*\\"|after: \\"'"${cursor}"'\\"|' <<< "${data}")
		result="${api_workdir}/result.${cursor}"

		if ! curl --request "${request}" \
				--url "https://${GITLAB_HOST}/api/graphql" \
				--header "Authorization: Bearer ${GITLAB_TOKEN}" \
				--header "Content-Type: application/json" \
				--data "${data}" \
				--output "${result}" \
				--silent; then
			msg_error "  api call failed: $(cat "${outfile}")"
			return 1
		fi

		hasNextPage=$(jq --raw-output ".data | .${node_type} | .pageInfo | .hasNextPage" < "${result}")
		cursor=$(jq --raw-output ".data | .${node_type} | .pageInfo | .endCursor" < "${result}")

		cp "${result}" "${api_workdir}/tmp"
		jq ".data.${node_type}.nodes" "${api_workdir}/tmp" > "${result}"
	done

	jq --slurp add "${api_workdir}"/result.* > "${outfile}"
	return 0
}

gitlab_api_call() {
	local outfile=$1
	local request=$2
	local endpoint=$3
	local data=${4:-}

	# empty token
	if [[ -z "${GITLAB_TOKEN}" ]]; then
		msg_error "  api call failed: No token provided"
		return 1
	fi

	if ! curl --request "${request}" \
			--url "https://${GITLAB_HOST}/api/v4/${endpoint}" \
			--header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
			--header "Content-Type: application/json" \
			--data "${data}" \
			--output "${outfile}" \
			--silent; then
		msg_error "  api call failed: $(cat "${outfile}")"
		return 1
	fi

	if ! gitlab_check_api_errors "${outfile}"; then
		return 1
	fi

	return 0
}

gitlab_api_call_paged() {
	local outfile=$1
	local status_file=$2
	local request=$3
	local endpoint=$4
	local data=${5:-}
	local result header

	# empty token
	if [[ -z "${GITLAB_TOKEN}" ]]; then
		msg_error "  api call failed: No token provided"
		return 1
	fi

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	api_workdir=$(mktemp --tmpdir="${WORKDIR}" --directory pkgctl-gitlab-api.XXXXXXXXXX)
	tmp_file=$(mktemp --tmpdir="${api_workdir}" spinner.tmp.XXXXXXXXXX)

	local next_page=1
	local total_pages=1

	while [[ -n "${next_page}" ]]; do
		percentage=$(( 100 * next_page / total_pages ))
		printf "📡 Querying GitLab: %s/%s [%s] %%spinner%%" \
			"${BOLD}${next_page}" "${total_pages}" "${percentage}%${ALL_OFF}"  \
			> "${tmp_file}"
		mv "${tmp_file}" "${status_file}"

		result="${api_workdir}/result.${next_page}"
		header="${api_workdir}/header"
		if ! curl --request "${request}" \
				--get \
				--url "https://${GITLAB_HOST}/api/v4/${endpoint}&per_page=100&page=${next_page}" \
				--header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
				--header "Content-Type: application/json" \
				--data-urlencode "${data}" \
				--dump-header "${header}" \
				--output "${result}" \
				--silent; then
			msg_error "  api call failed: $(cat "${result}")"
			return 1
		fi

		if ! gitlab_check_api_errors "${result}"; then
			return 1
		fi

		next_page=$(grep "x-next-page" "${header}" | tr -d '\r' | awk '{ print $2 }')
		total_pages=$(grep "x-total-pages" "${header}" | tr -d '\r' | awk '{ print $2 }')
	done

	jq --slurp add "${api_workdir}"/result.* > "${outfile}"
	return 0
}

gitlab_check_api_errors() {
	local file=$1
	local error

	# search API only returns an array, no errors
	if [[ $(jq --raw-output 'type' < "${file}") == "array" ]]; then
		return 0
	fi

	# check for general purpose api error
	if error=$(jq --raw-output --exit-status '.error' < "${file}"); then
		msg_error "  api call failed: ${error}"
		return 1
	fi

	# check for api specific error messages
	if ! jq --raw-output --exit-status '.id' < "${file}" >/dev/null; then
		if jq --raw-output --exit-status '.message | keys[]' < "${file}" &>/dev/null; then
			while read -r error; do
				msg_error "  api call failed: ${error}"
			done < <(jq --raw-output --exit-status '.message|to_entries|map("\(.key) \(.value[])")[]' < "${file}")
		elif error=$(jq --raw-output --exit-status '.message' < "${file}"); then
			msg_error "  api call failed: ${error}"
		fi
		return 1
	fi
	return 0
}

graphql_check_api_errors() {
	local file=$1
	local error

	# early exit if we do not have errors
	if ! jq --raw-output --exit-status '.errors[]' < "${file}" &>/dev/null; then
		return 0
	fi

	# check for api specific error messages
	while read -r error; do
		msg_error "  api call failed: ${error}"
	done < <(jq --raw-output --exit-status '.errors[].message' < "${file}")
	return 1
}

gitlab_api_get_user() {
	local outfile username

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api.XXXXXXXXXX)

	# query user details
	if ! gitlab_api_call "${outfile}" GET "user/"; then
		msg_warn "  Invalid token provided?"
		exit 1
	fi

	# extract username from details
	if ! username=$(jq --raw-output --exit-status '.username' < "${outfile}"); then
		msg_error "  failed to query username: $(cat "${outfile}")"
		return 1
	fi

	printf "%s" "${username}"
	return 0
}

gitlab_api_get_project_name_mapping() {
	local query=$1
	local outfile

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api.XXXXXXXXXX)

	# query user details
	if ! graphql_api_call "${outfile}" POST projects "${query}"; then
		msg_warn "  Invalid token provided?"
		exit 1
	fi

	cat "${outfile}"
	return 0
}

gitlab_lookup_project_names() {
	local status_file=$1; shift
	local project_ids=("$@")
	local graphql_lookup_batch=200

	local project_name_cache_file tmp_file from length percentage
	local project_slice query projects mapping_output

	# collect project ids whose name needs to be looked up
	project_name_cache_file=$(get_cache_file gitlab/project_id_to_name)
	lock 11 "${project_name_cache_file}" "Locking project name cache"

	# early exit if there is nothing new to look up
	if (( ! ${#project_ids[@]} )); then
		cat "${project_name_cache_file}"
		# close project name cache lock
		lock_close 11
		return
	fi

	# reduce project_ids to uncached entries
	mapfile -t project_ids < <(
		printf "%s\n" "${project_ids[@]}" | \
			grep --invert-match --file <(awk '{ print $1 }' < "${project_name_cache_file}" ))

	# look up project names
	tmp_file=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api-spinner.tmp.XXXXXXXXXX)
	local entries="${#project_ids[@]}"
	local until=0
	while (( until < entries )); do
		from=${until}
		until=$(( until + graphql_lookup_batch ))
		if (( until > entries )); then
			until=${entries}
		fi
		length=$(( until - from ))

		percentage=$(( 100 * until / entries ))
		printf "📡 Querying GitLab project names: %s/%s [%s] %%spinner%%" \
			"${BOLD}${until}" "${entries}" "${percentage}%${ALL_OFF}"  \
			> "${tmp_file}"
		mv "${tmp_file}" "${status_file}"

		project_slice=("${project_ids[@]:${from}:${length}}")
		printf -v projects '"gid://gitlab/Project/%s",' "${project_slice[@]}"
		query='{
			projects(after: "" ids: ['"${projects}"']) {
				pageInfo {
					startCursor
					endCursor
					hasNextPage
				}
				nodes {
					id
					name
				}
			}
		}'
		mapping_output=$(gitlab_api_get_project_name_mapping "${query}")

		# update cache
		while read -r project_id project_name; do
			printf "%s %s\n" "${project_id}" "${project_name}" >> "${project_name_cache_file}"
		done < <(jq --raw-output \
			'.[] | "\(.id | rindex("/") as $lastSlash | .[$lastSlash+1:]) \(.name)"' \
			<<< "${mapping_output}")
	done

	cat "${project_name_cache_file}"

	# close project name cache lock
	lock_close 11
}

longest_package_name_from_ids() {
	local project_ids=("$@")
	local longest=0

	# collect project ids whose name needs to be looked up
	project_name_cache_file=$(get_cache_file gitlab/project_id_to_name)
	lock 11 "${project_name_cache_file}" "Locking project name cache"

	# read project_id to name mapping from cache
	while read -r project_id project_name; do
		if (( ${#project_name} > longest )) && in_array "${project_id}" "${project_ids[@]}"; then
			longest="${#project_name}"
		fi
	done < "${project_name_cache_file}"

	# close project name cache lock
	lock_close 11

	printf "%s" "${longest}"
}

# Convert arbitrary project names to GitLab valid path names.
#
# GitLab has several limitations on project and group names and also maintains
# a list of reserved keywords as documented on their docs.
# https://docs.gitlab.com/ee/user/reserved_names.html
#
# 1. replace single '+' between word boundaries with '-'
# 2. replace any other '+' with literal 'plus'
# 3. replace any special chars other than '_', '-' and '.' with '-'
# 4. replace consecutive '_-' chars with a single '-'
# 5. replace 'tree' with 'unix-tree' due to GitLab reserved keyword
gitlab_project_name_to_path() {
	local name=$1
	printf "%s" "${name}" \
		| sed -E 's/([a-zA-Z0-9]+)\+([a-zA-Z]+)/\1-\2/g' \
		| sed -E 's/\+/plus/g' \
		| sed -E 's/[^a-zA-Z0-9_\-\.]/-/g' \
		| sed -E 's/[_\-]{2,}/-/g' \
		| sed -E 's/^tree$/unix-tree/g'
}

gitlab_api_create_project() {
	local pkgbase=$1
	local outfile data path project_path

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api.XXXXXXXXXX)

	project_path=$(gitlab_project_name_to_path "${pkgbase}")

	# create GitLab project
	data='{
		"name": "'"${pkgbase}"'",
		"path": "'"${project_path}"'",
		"namespace_id": "'"${GIT_PACKAGING_NAMESPACE_ID}"'",
		"request_access_enabled": "false"
	}'
	if ! gitlab_api_call "${outfile}" POST "projects/" "${data}"; then
		return 1
	fi

	if ! path=$(jq --raw-output --exit-status '.path' < "${outfile}"); then
		msg_error "  failed to query path: $(cat "${outfile}")"
		return 1
	fi

	printf "%s" "${path}"
	return 0
}

# TODO: parallelize
# https://docs.gitlab.com/ee/api/search.html#scope-blobs
gitlab_api_search() {
	local search=$1
	local status_file=$2
	local outfile

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api.XXXXXXXXXX)

	if ! gitlab_api_call_paged "${outfile}" "${status_file}" GET "/groups/archlinux%2fpackaging%2fpackages/search?scope=blobs" "search=${search}"; then
		return 1
	fi

	cat "${outfile}"

	return 0
}

# TODO: parallelize
# https://docs.gitlab.com/ee/api/issues.html#list-project-issues
gitlab_projects_issues_list() {
	local project=$1
	local status_file=$2
	local params=${3:-}
	local data=${4:-}
	local outfile

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api.XXXXXXXXXX)

	if ! gitlab_api_call_paged "${outfile}" "${status_file}" GET "/projects/archlinux%2fpackaging%2fpackages%2f${project}/issues?${params}" "${data}"; then
		return 1
	fi

	cat "${outfile}"

	return 0
}

# TODO: parallelize
# https://docs.gitlab.com/ee/api/issues.html#list-project-issues
gitlab_group_issue_list() {
	local group=$1
	local status_file=$2
	local params=${3:-}
	local data=${4:-}
	local outfile

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-gitlab-api.XXXXXXXXXX)

	group=${group//\//%2f}
	params=${params//\[/%5B}
	params=${params//\]/%5D}

	if ! gitlab_api_call_paged "${outfile}" "${status_file}" GET "/groups/${group}/issues?${params}" "${data}"; then
		return 1
	fi

	cat "${outfile}"

	return 0
}

gitlab_severity_from_labels() {
	local labels=("$@")
	local severity="unknown"
	local label
	for label in "${labels[@]}"; do
		if [[ ${label} == severity::* ]]; then
			severity="${label#*-}"
		fi
	done
	printf "%s" "${severity}"
}

severity_as_gitlab_label() {
	local severity=$1
	case "${severity}" in
		lowest)
			printf "severity::5-%s" "${severity}" ;;
		low)
			printf "severity::4-%s" "${severity}" ;;
		medium)
			printf "severity::3-%s" "${severity}" ;;
		high)
			printf "severity::2-%s" "${severity}" ;;
		critical)
			printf "severity::1-%s" "${severity}" ;;
		*)
			return 1 ;;
	esac
	return 0
}

gitlab_priority_from_labels() {
	local labels=("$@")
	local priority="normal"
	local label
	for label in "${labels[@]}"; do
		if [[ ${label} == priority::* ]]; then
			priority="${label#*-}"
		fi
	done
	printf "%s" "${priority}"
}

priority_as_gitlab_label() {
	local priority=$1
	case "${priority}" in
		low)
			printf "priority::4-%s" "${priority}" ;;
		normal)
			printf "priority::3-%s" "${priority}" ;;
		high)
			printf "priority::2-%s" "${priority}" ;;
		urgent)
			printf "priority::1-%s" "${priority}" ;;
		*)
			return 1 ;;
	esac
	return 0
}

gitlab_scope_from_labels() {
	local labels=("$@")
	local scope="unknown"
	local label
	for label in "${labels[@]}"; do
		if [[ ${label} == scope::* ]]; then
			scope="${label#*::}"
		fi
	done
	printf "%s" "${scope}"
}

scope_as_gitlab_label() {
	local scope=$1
	if ! in_array "${scope}" "${DEVTOOLS_VALID_ISSUE_SCOPE[@]}"; then
		return 1
	fi
	printf "scope::%s" "${scope}"
}

gitlab_scope_short() {
	local scope=$1
	case "${scope}" in
		regression)
			scope=regress ;;
		enhancement)
			scope=enhance ;;
		documentation)
			scope=doc ;;
		reproducibility)
			scope=repro ;;
		out-of-date)
			scope=ood ;;
	esac
	printf "%s" "${scope}"
}

gitlab_scope_color() {
	local scope=$1
	local color="${GRAY}"

	case "${scope}" in
		bug)
			color="${DARK_RED}" ;;
		feature)
			color="${DARK_BLUE}" ;;
		security)
			color="${RED}" ;;
		question)
			color="${PURPLE}" ;;
		regression)
			color="${DARK_RED}" ;;
		enhancement)
			color="${DARK_BLUE}" ;;
		documentation)
			color="${ALL_OFF}" ;;
		reproducibility)
			color="${DARK_GREEN}" ;;
		out-of-date)
			color="${DARK_YELLOW}" ;;
	esac

	printf "%s" "${color}"
}

status_as_gitlab_label() {
	local status=$1
	if ! in_array "${status}" "${DEVTOOLS_VALID_ISSUE_STATUS[@]}"; then
		return 1
	fi
	printf "status::%s" "${status}"
	return 0
}

gitlab_issue_state_display() {
	local state=$1
	if [[ ${state} == opened ]]; then
		state=open
	fi
	printf "%s" "${state}"
}

gitlab_issue_status_from_labels() {
	local labels=("$@")
	local status=unconfirmed
	local label
	for label in "${labels[@]}"; do
		if [[ ${label} == status::* ]]; then
			status="${label#*::}"
		fi
	done
	printf "%s" "${status}"
}

gitlab_issue_status_short() {
	local status=$1
	if [[ ${status} == waiting-* ]]; then
		status=waiting
	fi
	printf "%s" "${status}"
}

gitlab_issue_status_color() {
	local status=$1
	local color="${GRAY}"

	case "${status}" in
		confirmed)
			color="${GREEN}" ;;
		in-progress)
			color="${YELLOW}" ;;
		in-review)
			color="${PURPLE}" ;;
		on-hold|unconfirmed)
			color="${GRAY}" ;;
		waiting-input|waiting-upstream)
			color="${DARK_BLUE}" ;;
	esac

	printf "%s" "${color}"
}

resolution_as_gitlab_label() {
	local resolution=$1
	if ! in_array "${resolution}" "${DEVTOOLS_VALID_ISSUE_RESOLUTION[@]}"; then
		return 1
	fi
	printf "resolution::%s" "${resolution}"
}

gitlab_resolution_from_labels() {
	local labels=("$@")
	local label
	for label in "${labels[@]}"; do
		if [[ ${label} == resolution::* ]]; then
			printf "%s" "${label#*::}"
			return 0
		fi
	done
	return 1
}

gitlab_resolution_color() {
	local resolution=$1
	local color=""

	case "${resolution}" in
		cant-reproduce)
			color="${DARK_YELLOW}" ;;
		completed)
			color="${GREEN}" ;;
		duplicate)
			color="${GRAY}" ;;
		invalid)
			color="${DARK_YELLOW}" ;;
		not-a-bug)
			color="${GRAY}" ;;
		upstream)
			color="${PURPLE}" ;;
		wont-fix)
			color="${DARK_BLUE}" ;;
	esac

	printf "%s" "${color}"
}

gitlab_severity_color() {
	local severity=$1
	local color="${PURPLE}"

	case "${severity}" in
		lowest)
			color="${DARK_GREEN}" ;;
		low)
			color="${GREEN}" ;;
		medium)
			color="${YELLOW}" ;;
		high)
			color="${RED}" ;;
		critical)
			color="${RED}${UNDERLINE}" ;;
	esac

	printf "%s" "${color}"
}

gitlab_priority_color() {
	local priority=$1
	local color="${PURPLE}"

	case "${priority}" in
		low)
			color="${DARK_GREEN}" ;;
		normal)
			color="${GREEN}" ;;
		high)
			color="${YELLOW}" ;;
		urgent)
			color="${RED}" ;;
	esac

	printf "%s" "${color}"
}

gitlab_issue_state_color() {
	local state=$1
	local state_color="${DARK_GREEN}"

	if [[ ${state} == closed ]]; then
		state_color="${DARK_RED}"
	fi
	printf "%s" "${state_color}"
}
