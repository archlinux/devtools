#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_ISSUE_MOVE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_ISSUE_MOVE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/cache.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/cache.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

set -eo pipefail


pkgctl_issue_move_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [IID] [DESTINATION_PACKAGE]

		The move command allows users to transfer an issue from one project to another
		within the Arch Linux packaging group. This is useful when an issue is
		identified to be more relevant or better handled in a different project.

		By default, the command operates within the current directory, but users can
		specify a different package base from which to move the issue.

		Users must specify the issue ID (IID) and the destination package to which the
		issue should be moved. A comment message explaining the reason for the move can
		be provided directly through the command line.

		OPTIONS
		    -p, --package PKGBASE  Move from <pkgbase> instead of the current directory
		    -m, --message MSG      Use the provided message as the comment
		    -e, --edit             Edit the comment using an editor
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} 42 to-bar
		    $ ${COMMAND} --package from-foo 42 to-bar
_EOF_
}

pkgctl_issue_move() {
	if (( $# < 1 )); then
		pkgctl_issue_move_usage
		exit 0
	fi

	local iid=""
	local pkgbase=""
	local message=""
	local edit=0

	local to_project_name to_project_id project_path issue_url to_iid result

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_issue_move_usage
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
				break
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

	if (( $# < 2 )); then
		pkgctl_issue_move_usage
		exit 1
	fi

	iid=$1
	to_project_name=$(basename "$2")

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

	if ! result=$(gitlab_project "${to_project_name}"); then
		msg_error "Failed to query target project ${BOLD}${to_project_name}${ALL_OFF}"
		exit 1
	fi

	if ! to_project_id=$(jq --raw-output ".id" <<< "${result}"); then
		msg_error "Failed to query project id for ${BOLD}${to_project_name}${ALL_OFF}"
		exit 1
	fi

	# comment on issue
	if [[ -n ${message} ]]; then
		if ! result=$(gitlab_create_project_issue_note "${pkgbase}" "${iid}" "${message}"); then
			msg_error "Failed to comment on issue ${BOLD}#${iid}${ALL_OFF}"
			exit 1
		fi
		msg_success "Commented on issue ${BOLD}#${iid}${ALL_OFF}"
	fi

	if ! result=$(gitlab_project_issue_move "${pkgbase}" "${iid}" "${to_project_id}"); then
		msg_error "Failed to move issue ${BOLD}#${iid}${ALL_OFF} to ${BOLD}${to_project_name}${ALL_OFF}"
		exit 1
	fi

	if ! to_iid=$(jq --raw-output ".iid" <<< "${result}"); then
		msg_error "Failed to query issue id for ${BOLD}${to_project_name}${ALL_OFF}"
		exit 1
	fi

	project_path=$(gitlab_project_name_to_path "${to_project_name}")
	issue_url="${GIT_PACKAGING_URL_HTTPS}/${project_path}/-/issues/${to_iid}"

	msg_success "Moved issue ${BOLD}${pkgbase}${ALL_OFF} ${BOLD}#${iid}${ALL_OFF} to ${BOLD}${to_project_name}${ALL_OFF} ${BOLD}#${to_iid}${ALL_OFF}"
	echo
	printf "%sView this issue on GitLab: %s%s\n" "${GRAY}" "${issue_url}" "${ALL_OFF}"
}
