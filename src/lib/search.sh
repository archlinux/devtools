#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_SEARCH_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_SEARCH_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/cache.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/cache.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail


pkgctl_search_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] QUERY

		Search for an expression across the GitLab packaging group.

		To use a filter, include it in your query. You may use wildcards (*) to
		use glob matching.

		Available filters for the blobs scope: path, extension

		Every usage of the search command must be authenticated. Consult the
		'pkgctl auth' command to authenticate with GitLab or view the
		authentication status.

		SEARCH TIPS
		    Syntax  Description    Example
		    ───────────────────────────────────────
		    "       Exact search   "gem sidekiq"
		    ~       Fuzzy search   J~ Doe
		    |       Or             display | banner
		    +       And            display +banner
		    -       Exclude        display -banner
		    *       Partial        bug error 50*
		    \\       Escape         \\*md
		    #       Issue ID       #23456
		    !       Merge request  !23456

		OPTIONS
		    --json               Enable printing results in JSON
		    --no-default-filter  Do not apply default filter (like -path:keys/pgp/*.asc)
		    -h, --help           Show this help text

		EXAMPLES
		    $ ${COMMAND} linux
		    $ ${COMMAND} '"pytest -v" +PYTHONPATH'
_EOF_
}

pkgctl_search() {
	if (( $# < 1 )); then
		pkgctl_search_usage
		exit 0
	fi

	# options
	local search
	local formatter=pretty
	local use_default_filter=1

	# variables
	local default_filter="-path:keys/pgp/*.asc"
	local graphql_lookup_batch=200
	local output result query entries from until length
	local project_name_cache_file project_name_lookup project_ids project_id project_name project_slice
	local mapping_output path startline data

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_search_usage
				exit 0
				;;
			--json)
				formatter=json
				shift
				;;
			--no-default-filter)
				use_default_filter=0
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
				break
				;;
		esac
	done

	if (( $# == 0 )); then
		pkgctl_search_usage
		exit 1
	fi

	# assign search parameter
	search="${*}"
	if (( use_default_filter )); then
		search+=" ${default_filter}"
	fi

	stat_busy "Querying gitlab search api"
	output=$(gitlab_api_search "${search}")
	stat_done

	project_name_cache_file=$(get_cache_file gitlab/project_id_to_name)
	lock 11 "${project_name_cache_file}" "Locking project name cache"
	mapfile -t project_ids < <(
		jq --raw-output '[.[].project_id] | unique[]' <<< "${output}" | \
			grep --invert-match --file <(awk '{ print $1 }' < "${project_name_cache_file}" ))

	stat_busy "Querying project names"
	local entries="${#project_ids[@]}"
	local until=0
	while (( until < entries )); do
		from=${until}
		until=$(( until + graphql_lookup_batch ))
		if (( until > entries )); then
			until=${entries}
		fi
		length=$(( until - from ))

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
	stat_done

	# read project_id to name mapping from cache
	declare -A project_name_lookup=()
	while read -r project_id project_name; do
		project_name_lookup[${project_id}]=${project_name}
	done < "${project_name_cache_file}"

	# close project name cache lock
	lock_close 11

	# output mode JSON
	if [[ ${formatter} == json ]]; then
		jq --from-file <(
			for project_id in $(jq '.[].project_id' <<< "${output}"); do
				project_name=${project_name_lookup[${project_id}]}
				printf 'map(if .project_id == %s then . + {"project_name": "%s"} else . end) | ' \
					"${project_id}" "${project_name}"
			done
			printf .
		) <<< "${output}"
		exit 0
	fi

	# pretty print each result
	while read -r result; do
		# read properties from search result
		mapfile -t data < <(jq --raw-output ".data" <<< "${result}")
		{ read -r project_id; read -r path; read -r startline; } < <(
			jq --raw-output ".project_id, .path, .startline" <<< "${result}"
		)
		project_name=${project_name_lookup[${project_id}]}

		# remove trailing newline for multiline results
		if (( ${#data[@]} > 1 )) && [[ ${data[-1]} == "" ]]; then
			unset "data[${#data[@]}-1]"
		fi

		# prepend empty lines to match startline
		if (( startline > 1 )); then
			mapfile -t data < <(
				printf '%.0s\n' $(seq 1 "$(( startline - 1 ))")
				printf "%s\n" "${data[@]}"
			)
		fi

		bat \
			--file-name="${project_name}/${path}" \
			--line-range "${startline}:" \
			--paging=never \
			--force-colorization \
			--map-syntax "PKGBUILD:Bourne Again Shell (bash)" \
			--map-syntax ".SRCINFO:INI" \
			--map-syntax "*install:Bourne Again Shell (bash)" \
			--map-syntax "*sysusers*:Bourne Again Shell (bash)" \
			--map-syntax "*tmpfiles*:Bourne Again Shell (bash)" \
			--map-syntax "*.hook:INI" \
			<(printf "%s\n" "${data[@]}")
	done < <(jq --compact-output '.[]' <<< "${output}")
}
