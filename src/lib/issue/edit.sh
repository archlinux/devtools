#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_EDIT_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_EDIT_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

set -eo pipefail


pkgctl_issue_edit_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [IID]

		The pkgctl issue edit command is used to modify an existing issue in Arch Linux
		packaging projects. This command allows users to update the issue's title,
		description, and various attributes, ensuring that the issue information
		remains accurate and up-to-date. It also provides a streamlined facility
		for bug wranglers to categorize and prioritize issues efficiently.

		By default, the command operates within the current directory, but users can
		specify a different package base if needed.

		In case of a failed run, the command can automatically recover to ensure that
		the editing process is completed without losing any data.

		OPTIONS
		    -p, --package PKGBASE   Interact with <pkgbase> instead of the current directory
		    -t, --title TITLE       Use the provided title for the issue
		    -e, --edit              Edit the issue title and description using an editor
		    --recover               Automatically recover from a failed run
		    --confidentiality TYPE  Set the issue confidentiality
		    --priority PRIORITY     Set the priority label
		    --resolution REASON     Set the resolution label
		    --scope SCOPE           Set the scope label
		    --severity SEVERITY     Set the severity label
		    --status STATUS         Set the status label
		    -h, --help              Show this help text

		EXAMPLES
		    $ ${COMMAND} --package linux --title "some very informative title"
_EOF_
}

pkgctl_issue_edit() {
	if (( $# < 1 )); then
		pkgctl_issue_edit_usage
		exit 0
	fi

	local pkgbase=""
	local title=""
	local description=""
	local labels=()
	local confidential=""
	local msgfile=""
	local edit=0
	local recover=0

	local recovery_home=${XDG_DATA_HOME:-$HOME/.local/share}/devtools/recovery
	local recovery_file
	local issue_url
	local project_path
	local result
	local iid
	local message

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_edit_usage
				exit 0
				;;
			-p|--package)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgbase=$2
				shift 2
				;;
			-t|--title)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				title=$2
				shift 2
				;;
			-e|--edit)
				edit=1
				shift
				;;
			--recover)
				recover=1
				shift
				;;
			--confidentiality)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! in_array "$2" "${DEVTOOLS_VALID_ISSUE_CONFIDENTIALITY[@]}"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				if [[ $2 == public ]]; then
					confidential=false
				else
					confidential=true
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
	recovery_file="${recovery_home}/issue_edit_${pkgbase}.md"

	# load current issue data
	if ! result=$(gitlab_project_issue "${pkgbase}" "${iid}"); then
		die "Failed to query issue ${pkgbase} #${iid}"
	fi
	{ read -r current_title; read -r current_confidential; } < <(
		jq --raw-output ".title, .confidential" <<< "${result}"
	)
	current_description=$(jq --raw-output ".description" <<< "${result}")

	# check existence of recovery file
	if [[ -f ${recovery_file} ]]; then
		if (( ! recover )); then
			msg_warn "Recovery file already exists: ${recovery_file}"
			if prompt "${GREEN}${BOLD}?${ALL_OFF} Do you want to recover?"; then
				msgfile=${recovery_file}
				recover=1
				edit=1
			fi
		fi
	fi

	# assign data to msgfile
	if [[ -n ${msgfile} ]]; then
		# check existence of msgfile
		if [[ ! -f ${msgfile} ]]; then
			msg_error "File does not exist: ${msgfile}${ALL_OFF}"
			exit 1
		fi
	fi

	# spawn editor
	if (( edit )); then
		if [[ -z ${msgfile} ]]; then
			msgfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-issue-create.XXXXXXXXXX.md)
			if [[ -n ${title} ]]; then
				printf "# Title: %s\n\n" "${title}" >> "${msgfile}"
			else
				printf "# Title: %s\n\n" "${current_title}" >> "${msgfile}"
			fi
			printf "%s\n" "${current_description}" >> "${msgfile}"
		fi

		if [[ -n $VISUAL ]]; then
			editor=${VISUAL}
		elif [[ -n $EDITOR ]]; then
			editor=${EDITOR}
		else
			die "No usable editor found (tried \$VISUAL, \$EDITOR)."
		fi

		if ! ${editor} "${msgfile}"; then
			message=$(< "${msgfile}")
			pkgctl_issue_write_recovery_file "${pkgbase}" "${message}" "${recovery_file}" "${recover}"
			return 1
		fi
	fi

	# check if the file contains a title
	if [[ -n ${msgfile} ]]; then
		message=$(< "${msgfile}")
		description=${message}
		if [[ ${message} == "# Title: "* ]]; then
			title=$(head --lines 1 <<< "${message}")
			title=${title//# Title: /}
			description=$(tail --lines +2 <<< "${message}")
			if [[ ${description} == $'\n'* ]]; then
				description=$(tail --lines +3 <<< "${message}")
			fi
		fi
	fi

	# prepare changes
	data='{}'
	if [[ -n ${title} ]] && [[ ${title} != "${current_title}" ]]; then
		result=$(jq --null-input \
			--arg title "${title}" \
			'$ARGS.named')
		data=$(jq --slurp '.[0] * .[1]' <(echo "${data}") <(echo "${result}"))
	fi
	if [[ -n ${description} ]] && [[ ${description} != "${current_description}" ]]; then
		result=$(jq --null-input \
			--arg description "${description}" \
			'$ARGS.named')
		data=$(jq --slurp '.[0] * .[1]' <(echo "${data}") <(echo "${result}"))
	fi
	if [[ -n ${confidential} ]] && [[ ${confidential} != "${current_confidential}" ]]; then
		result=$(jq --null-input \
			--arg confidential "${confidential}" \
			'$ARGS.named')
		data=$(jq --slurp '.[0] * .[1]' <(echo "${data}") <(echo "${result}"))
	fi
	if (( ${#labels[@]} )); then
		result=$(jq --null-input \
			--arg add_labels "$(join_by , "${labels[@]}")" \
			'$ARGS.named')
		data=$(jq --slurp '.[0] * .[1]' <(echo "${data}") <(echo "${result}"))
	fi

	# edit the issue
	if ! result=$(gitlab_project_issue_edit "${pkgbase}" "${iid}" "${params}" "${data}"); then
		msg_error "Failed to edit issue ${BOLD}${pkgbase}${ALL_OFF} #${iid}"
		pkgctl_issue_write_recovery_file "${pkgbase}" "${message}" "${recovery_file}" "${recover}"
		exit 1
	fi

	# delete old recovery file if we succeeded
	if [[ -f ${recovery_file} ]]; then
		rm --force "${recovery_file}"
	fi

	issue_url="${GIT_PACKAGING_URL_HTTPS}/${project_path}/-/issues/${iid}"
	msg_success "Updated issue ${BOLD}#${iid}${ALL_OFF}"
	printf "%sView this issue on GitLab: %s%s\n" "${GRAY}" "${issue_url}" "${ALL_OFF}"
}

pkgctl_issue_write_recovery_file() {
	local pkgbase=$1
	local message=$2
	local recovery_file=$3

	if [[ -f ${recovery_file} ]]; then
		msg_warn "Recovery file already exists: ${recovery_file}"
		if ! prompt "${YELLOW}${BOLD}?${ALL_OFF} Are you sure you want to overwrite it?"; then
			return 1
		fi
	fi

	mkdir -p "$(dirname "${recovery_file}")"
	printf "%s\n" "${message}" > "${recovery_file}"

	printf "Created recovery file: %s\n" "${recovery_file}"
	return 0
}
