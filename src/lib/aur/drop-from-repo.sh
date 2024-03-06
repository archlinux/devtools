#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_AUR_DROP_FROM_REPO_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_AUR_DROP_FROM_REPO_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/db/remove.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/db/remove.sh
# shellcheck source=src//lib/util/pacman.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pacman.sh

source /usr/share/makepkg/util/message.sh

set -eo pipefail


pkgctl_aur_drop_from_repo_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PATH]...

		Drops a specified package from the official repositories to the Arch
		User Repository.

		This command requires a local Git clone of the package repository. It
		reconfigures the repository for AUR compatibility and pushes it to the
		AUR. Afterwards, the package is removed from the official repository.

		By default, the package is automatically disowned in the AUR.

		OPTIONS
		    --no-disown    Do not disown the package on the AUR
		    -f, --force    Force push to the AUR overwriting the remote repository
		    -h, --help     Show this help text

		EXAMPLES
		    $ ${COMMAND} foo
		    $ ${COMMAND} --no-disown --force
_EOF_
}

pkgctl_aur_drop_from_repo() {
	# options
	local paths=()
	local DISOWN=1
	local FORCE=0

	# variables
	local path realpath pkgbase pkgrepo remote_url

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_aur_drop_from_repo_usage
				exit 0
				;;
			--no-disown)
				DISOWN=0
				shift
				;;
			-f|--force)
				FORCE=1
				shift
				;;
			--)
				shift
				break
				;;
			-*)
				die "Invalid argument: %s" "$1"
				;;
			*)
				paths=("$@")
				break
				;;
		esac
	done

	# check if invoked without any path from within a packaging repo
	if (( ${#paths[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			paths=(".")
		else
			pkgctl_aur_drop_from_repo_usage
			exit 1
		fi
	fi

	for path in "${paths[@]}"; do
		# resolve symlink for basename
		if ! realpath=$(realpath --canonicalize-existing -- "${path}"); then
			die "No such directory: ${path}"
		fi
		# skip paths that are not directories
		if [[ ! -d "${realpath}" ]]; then
			continue
		fi

		pkgbase=$(basename "${realpath}")
		pkgbase=${pkgbase%.git}

		if [[ ! -d "${realpath}/.git" ]]; then
			die "Not a Git repository: ${path}"
		fi

		pushd "${path}" >/dev/null

		if [[ ! -f PKGBUILD ]]; then
			die 'PKGBUILD not found in %s' "${path}"
		fi

		msg "Dropping ${pkgbase} to the AUR"

		remote_url="${AUR_URL_SSH}:${pkgbase}.git"
		if ! git remote add origin "${remote_url}" &>/dev/null; then
			git remote set-url origin "${remote_url}"
		fi

		# move the main branch to master
		if [[ $(git symbolic-ref --quiet --short HEAD) == main ]]; then
			git branch --move master
			git config branch.master.merge refs/heads/master
		fi

		# auto generate .SRCINFO if not already present
		if [[ -z "$(git ls-tree -r HEAD --name-only .SRCINFO)" ]]; then
			stat_busy 'Generating .SRCINFO'
			makepkg --printsrcinfo > .SRCINFO
			stat_done

			git add --force -- .SRCINFO
			git commit --quiet --message "Adding .SRCINFO" -- .SRCINFO
		fi

		msg "Pushing ${pkgbase} to the AUR"
		if (( FORCE )); then
			AUR_OVERWRITE=1 \
				GIT_SSH_COMMAND="ssh -o SendEnv=AUR_OVERWRITE" \
				git push --force --no-follow-tags origin master
		else
			git push --no-follow-tags origin master
		fi

		# update the local default branch in case this clone is used in the future
		git remote set-head origin master

		if (( DISOWN )); then
			msg "Disowning ${pkgbase} on the AUR"
			# shellcheck disable=SC2029
			ssh "${AUR_URL_SSH}" disown "${pkgbase}"
		fi

		# auto-detection of the repo to remove from
		if ! pkgrepo=$(get_pacman_repo_from_pkgbuild PKGBUILD); then
			die 'Failed to get pacman repo'
		fi

		msg "Deleting ${pkgbase} from the official repository"
		if [[ -z "${pkgrepo}" ]]; then
			warning 'Did not find %s in any repository, please delete manually' "${pkgbase}"
		else
			msg2 "  repo: ${pkgrepo}"
			pkgctl_db_remove "${pkgrepo}" "${pkgbase}"
		fi

		popd >/dev/null
	done
}
