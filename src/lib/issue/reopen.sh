#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_REOPEN_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_REOPEN_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -eo pipefail


pkgctl_issue_reopen_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [IID]

		The reopen command is used to reopen a previously closed issue in Arch Linux
		packaging projects. This command is useful when an issue needs to be revisited
		or additional work is required after it was initially closed.

		By default, the command operates within the current directory, but users can
		specify a different package base if needed.

		Users can provide a message directly through the command line to explain the
		reason for reopening the issue.

		OPTIONS
		    -p, --package PKGBASE  Interact with <pkgbase> instead of the current directory
		    -m, --message MSG      Use the provided message as the comment
		    -e, --edit             Edit the comment using an editor
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} 42
		    $ ${COMMAND} --package linux 42
_EOF_
}

pkgctl_issue_reopen() {
	if (( $# < 1 )); then
		pkgctl_issue_reopen_usage
		exit 0
	fi

	local iid=""
	local pkgbase=""
	local message=""
	local edit=0

	local issue note result resolution labels
	local params="state_event=reopen"

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_reopen_usage
				exit 0
				;;
			-p|--package)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgbase=$2
				shift 2
				;;
			-m|--message)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				message=$2
				shift 2
				;;
			-e|--edit)
				edit=1
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


	# spawn editor
	if (( edit )); then
		msgfile=$(mktemp --tmpdir="${WORKDIR}" pkgctl-issue-note.XXXXXXXXXX.md)
		printf "%s\n" "${message}" >> "${msgfile}"
		if [[ -n $VISUAL ]]; then
			$VISUAL "${msgfile}" || die
		elif [[ -n $EDITOR ]]; then
			$EDITOR "${msgfile}" || die
		else
			die "No usable editor found (tried \$VISUAL, \$EDITOR)."
		fi
		message=$(< "${msgfile}")
	fi

	# query issue details
	if ! result=$(gitlab_project_issue "${pkgbase}" "${iid}"); then
		die "Failed to fetch issue ${pkgbase} #${iid}"
	fi
	mapfile -t labels < <(
		jq --raw-output ".labels[]" <<< "${result}"
	)
	if resolution=$(gitlab_resolution_from_labels "${labels[@]}"); then
		resolution=$(resolution_as_gitlab_label "${resolution}")
		params+="&remove_labels=${resolution}"
	fi

	# comment on issue
	if [[ -n ${message} ]]; then
		if ! note=$(gitlab_create_project_issue_note "${pkgbase}" "${iid}" "${message}"); then
			msg_error "Failed to comment on issue ${BOLD}#${iid}${ALL_OFF}"
			exit 1
		fi
		msg_success "Commented on issue ${BOLD}#${iid}${ALL_OFF}"
	fi

	# reopen issue
	if ! issue=$(gitlab_project_issue_edit "${pkgbase}" "${iid}" "${params}"); then
		msg_error "Failed to reopen issue ${BOLD}#${iid}${ALL_OFF}"
		exit 1
	fi
	msg_success "Reopened issue ${BOLD}#${iid}${ALL_OFF}"
	echo

	{ read -r iid; read -r title; read -r state; read -r created_at; read -r author; } < <(
		jq --raw-output ".iid, .title, .state, .created_at, .author.username" <<< "${issue}"
	)
	mapfile -t labels < <(
		jq --raw-output ".labels[]" <<< "${issue}"
	)

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

	printf "%s%s • %sseverity %s • %s • %s%sopened by %s %s ago%s\n" \
		"${state_color}${state}${ALL_OFF}" "${GRAY}" "${severity_color}" "${severity}${GRAY}" \
		"${status_color}${status}${GRAY}" "${scope_label}" "${GRAY}" "${author}" "${created_at}" "${ALL_OFF}"
	printf "%s %s\n" "${BOLD}${title}${ALL_OFF}" "${GRAY}#${iid}${ALL_OFF}"

	# show comment
	if [[ -n ${note} ]]; then
		{ read -r created_at; read -r author; } < <(
			jq --raw-output ".created_at, .author.username" <<< "${note}"
		)
		body=$(jq --raw-output ".body" <<< "${note}")
		created_at=$(relative_date_unit "${created_at}")

		echo
		echo "${BOLD}Comments / Notes${ALL_OFF}"
		printf -v spaces '%*s' $(( COLUMNS - 2 )) ''
		printf '%s\n\n' "${spaces// /─}"

		printf "%s commented%s %s ago%s\n" "${author}" "${GRAY}" "${created_at}" "${ALL_OFF}"
		echo "${body}" | glow
	fi
}
