#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_CREATE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_CREATE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh
# shellcheck source=src/lib/util/term.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/term.sh

set -eo pipefail


pkgctl_issue_create_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS]

		The create command is used to create a new issue for an Arch Linux package.
		This command is suitable for reporting bugs, regressions, feature requests, or
		any other issues related to a package. It provides a flexible way to document
		and track new issues within the project's issue tracking system.

		By default, the command operates within the current directory, but users can
		specify a different package base if needed.

		Users can provide a title for the issue directly through the command line.
		The command allows setting various labels and attributes for the issue, such as
		confidentiality, priority, scope, severity, and status.

		In case of a failed run, the command can automatically recover to ensure that
		the issue creation process is completed without losing any data.

		OPTIONS
		    -p, --package PKGBASE    Interact with <pkgbase> instead of the current directory
		    -t, --title TITLE        Use the provided title for the issue
		    -F, --file FILE          Take issue description from <file>
		    -e, --edit               Edit the issue description using an editor
		    -w, --web                Continue issue creation with the web interface
		    --recover                Automatically recover from a failed run
		    --confidentiality TYPE   Set the issue confidentiality
		    --priority PRIORITY      Set the priority label
		    --scope SCOPE            Set the scope label
		    --severity SEVERITY      Set the severity label
		    --status STATUS          Set the status label
		    -h, --help               Show this help text

		EXAMPLES
		    $ ${COMMAND} --package linux --title "some very informative title"
_EOF_
}

pkgctl_issue_create() {
	if (( $# < 1 )); then
		pkgctl_issue_create_usage
		exit 0
	fi

	local pkgbase=""
	local title_placeholder="PLACEHOLDER"
	local title="${title_placeholder}"
	local description=""
	local labels=()
	local msgfile=""
	local edit=0
	local web=0
	local recover=0
	local confidential=0

	local issue_template_url="https://gitlab.archlinux.org/archlinux/packaging/templates/-/raw/master/.gitlab/issue_templates/Default.md"
	local issue_template
	local recovery_home=${XDG_DATA_HOME:-$HOME/.local/share}/devtools/recovery
	local recovery_file
	local issue_url
	local project_path
	local result
	local iid
	local message
	local editor

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_create_usage
				exit 0
				;;
			-t|--title)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				title=$2
				shift 2
				;;
			-p|--package)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgbase=$2
				shift 2
				;;
			-F|--file)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				msgfile=$2
				shift 2
				;;
			-e|--edit)
				edit=1
				shift
				;;
			-w|--web)
				web=1
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
				if [[ $2 == confidential ]]; then
					confidential=1
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
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done

	if [[ -z ${pkgbase} ]]; then
		if ! [[ -f PKGBUILD ]]; then
			die "missing --package option or PKGBUILD in current directory"
		fi
		pkgbase=$(realpath --canonicalize-existing .)
	fi
	pkgbase=$(basename "${pkgbase}")
	project_path=$(gitlab_project_name_to_path "${pkgbase}")
	recovery_file="${recovery_home}/issue_create_${pkgbase}.md"

	# spawn web browser
	if (( web )); then
		if ! command -v xdg-open &>/dev/null; then
			die "The web option requires 'xdg-open'"
		fi
		issue_url="${GIT_PACKAGING_URL_HTTPS}/${project_path}/-/issues/new"
		echo "Opening ${issue_url} in your browser."
		xdg-open "${issue_url}"
		return
	fi

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

	# check existence of msgfile
	if [[ -n ${msgfile} ]]; then
		if [[ ! -f ${msgfile} ]]; then
			msg_error "File does not exist: ${msgfile}${ALL_OFF}"
			exit 1
		fi
	else
		# prepare msgfile and fetch the issue template
		if ! issue_template=$(curl --url "${issue_template_url}" --silent); then
			msg_error "Failed to fetch issue template${ALL_OFF}"
			exit 1
		fi
		# populate message file
		msgfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-issue-create.XXXXXXXXXX.md)
		edit=1
		printf "# Title: %s\n\n" "${title}" >> "${msgfile}"
		printf "%s\n" "${issue_template}" >> "${msgfile}"
	fi

	# spawn editor
	if (( edit )); then
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
		fi
	fi

	# check if the file contains a title
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

	# validate title
	if [[ ${title} == 'PLACEHOLDER' ]]; then
		msg_error "Invalid issue title: ${title}${ALL_OFF}"
		pkgctl_issue_write_recovery_file "${pkgbase}" "${message}" "${recovery_file}" "${recover}"
		exit 1
	fi

	# create the issue
	if ! result=$(gitlab_project_issue_create "${pkgbase}" "${title}" "${description}" "${confidential}" "${labels[@]}"); then
		msg_error "Failed to create issue in ${BOLD}${pkgbase}${ALL_OFF}"
		pkgctl_issue_write_recovery_file "${pkgbase}" "${message}" "${recovery_file}" "${recover}"
		exit 1
	fi

	# delete old recovery file if we succeeded
	if [[ -f ${recovery_file} ]]; then
		rm --force "${recovery_file}"
	fi

	# read issue iid
	{ read -r iid; } < <(
		jq --raw-output ".iid" <<< "${result}"
	)
	issue_url="${GIT_PACKAGING_URL_HTTPS}/${project_path}/-/issues/${iid}"

	msg_success "Created new issue ${BOLD}#${iid}${ALL_OFF}"
	printf "%sView this issue on GitLab: %s%s\n" "${GRAY}" "${issue_url}" "${ALL_OFF}"
}

pkgctl_issue_write_recovery_file() {
	local pkgbase=$1
	local message=$2
	local recovery_file=$3
	local recover=$4

	if [[ -f ${recovery_file} ]] && (( ! recover )); then
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
