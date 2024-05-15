#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_COMMENT_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_COMMENT_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -eo pipefail


pkgctl_issue_comment_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [IID]

		This command allows users to add comments to an issue in Arch Linux packaging
		projects. This command is useful for providing feedback, updates, or any
		additional information related to an issue directly within the project's issue
		tracking system.

		By default, the command interacts with the current directory, but users can
		specify a different package base if needed.

		OPTIONS
		    -p, --package PKGBASE  Interact with <pkgbase> instead of the current directory
		    -m, --message MSG      Use the provided message as the comment
		    -e, --edit             Edit the comment using an editor
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} --message "I've attached some logs" 42
		    $ ${COMMAND} --package linux 42
		    $ ${COMMAND} 42
_EOF_
}

pkgctl_issue_comment() {
	if (( $# < 1 )); then
		pkgctl_issue_comment_usage
		exit 0
	fi

	local iid=""
	local pkgbase=""
	local message=""
	local edit=0

	local note

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_comment_usage
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
	if (( edit )) || [[ -z ${message} ]]; then
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

	# comment on issue
	if ! note=$(gitlab_create_project_issue_note "${pkgbase}" "${iid}" "${message}"); then
		msg_error "Failed to comment on issue ${BOLD}#${iid}${ALL_OFF}"
		exit 1
	fi
	msg_success "Commented on issue ${BOLD}#${iid}${ALL_OFF}"
	echo

	{ read -r created_at; read -r author; } < <(
		jq --raw-output ".created_at, .author.username" <<< "${note}"
	)
	body=$(jq --raw-output ".body" <<< "${note}")
	created_at=$(relative_date_unit "${created_at}")

	printf "%s commented%s %s ago%s\n" "${author}" "${GRAY}" "${created_at}" "${ALL_OFF}"
	echo "${body}" | glow
}
