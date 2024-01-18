#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_API_GITLAB_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_API_GITLAB_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/config.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/config.sh

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
