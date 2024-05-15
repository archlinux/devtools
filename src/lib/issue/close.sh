#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_CLOSE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_CLOSE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -eo pipefail


pkgctl_issue_close_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [IID]

		This command is used to close an issue in Arch Linux packaging projects. It
		finalizes the issue by marking it as resolved and optionally providing a reason
		for its closure.

		By default, the command operates within the current directory, but users have
		the option to specify a different package base.

		Users can provide a message directly through the command line to explain the
		reason for closing the issue. Additionally, a specific resolution label can be
		set to categorize the closure reason, with the default label being "completed."

		OPTIONS
		    -p, --package PKGBASE    Interact with <pkgbase> instead of the current directory
		    -m, --message MSG        Use the provided message as the reason for closing
		    -e, --edit               Edit the reason for closing using an editor
		    -r, --resolution REASON  Set a specific resolution label (default: completed)
		    -h, --help               Show this help text

		EXAMPLES
		    $ ${COMMAND} 42
		    $ ${COMMAND} --edit --package linux 42
_EOF_
}

pkgctl_issue_close() {
	if (( $# < 1 )); then
		pkgctl_issue_close_usage
		exit 0
	fi

	local iid=""
	local pkgbase=""
	local message=""
	local edit=0
	local labels=()
	local resolution="completed"

	local issue note
	local params="state_event=close"

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_close_usage
				exit 0
				;;
			-m|--message)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				message=$2
				shift 2
				;;
			-p|--package)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgbase=$2
				shift 2
				;;
			-e|--edit)
				edit=1
				shift
				;;
			--resolution)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! label="$(resolution_as_gitlab_label "$2")"; then
					die "invalid argument for %s: %s" "$1" "$2"
				fi
				params+="&add_labels=${label}"
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
		message=$(cat "${msgfile}")
	fi

	# comment on issue
	if [[ -n ${message} ]]; then
		if ! note=$(gitlab_create_project_issue_note "${pkgbase}" "${iid}" "${message}"); then
			msg_error "Failed to comment on issue ${BOLD}#${iid}${ALL_OFF}"
			exit 1
		fi
		msg_success "Commented on issue ${BOLD}#${iid}${ALL_OFF}"
	fi

	# close issue
	if ! issue=$(gitlab_project_issue_edit "${pkgbase}" "${iid}" "${params}"); then
		msg_error "Failed to close issue ${BOLD}#${iid}${ALL_OFF}"
		exit 1
	fi
	msg_success "Closed issue ${BOLD}#${iid}${ALL_OFF}"
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

	resolution_label=""
	if resolution="$(gitlab_resolution_from_labels "${labels[@]}")"; then
		resolution_color="$(gitlab_resolution_color "${resolution}")"
		resolution_label="${resolution_color}${resolution}${ALL_OFF} ${GRAY}•${ALL_OFF} "
	fi

	printf "%s%s • %s%sseverity %s • %s • %s%sopened by %s %s ago%s\n" \
		"${state_color}${state}${ALL_OFF}" "${GRAY}" "${resolution_label}" "${severity_color}" "${severity}${GRAY}" \
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
