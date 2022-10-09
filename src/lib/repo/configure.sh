#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_CONFIGURE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_CONFIGURE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/api/gitlab.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/api/gitlab.sh

source /usr/share/makepkg/util/config.sh
source /usr/share/makepkg/util/message.sh

set -e


pkgctl_repo_configure_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PATH]...

		Configure Git packaging repositories according to distro specs and
		makepkg.conf settings.

		Git author information and the used signing key is set up from
		makepkg.conf read from any valid location like /etc or XDG_CONFIG_HOME.
		The unprivileged option can be used for cloning packaging repositories
		without SSH access using read-only HTTPS.

		OPTIONS
		    -u, --unprivileged   Configure read-only repo without packager info as Git author
		    -h, --help           Show this help text

		EXAMPLES
		    $ ${COMMAND} configure *
_EOF_
}

pkgctl_repo_configure() {
	# options
	local GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_SSH}
	local UNPRIVILEGED=0
	local PACKAGER_NAME=
	local PACKAGER_EMAIL=
	local paths=()

	# variables
	local path realpath pkgbase remote_url

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_configure_usage
				exit 0
				;;
			-u|--unprivileged)
				GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_HTTPS}
				UNPRIVILEGED=1
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
			pkgctl_repo_configure_usage
			exit 1
		fi
	fi

	# Load makepkg.conf variables to be available
	# shellcheck disable=2119
	load_makepkg_config

	# Check official packaging identity before setting Git author
	if (( ! UNPRIVILEGED )); then
		if [[ $PACKAGER == *"Unknown Packager"* ]]; then
			die "Packager must be set in makepkg.conf"
		fi
		packager_pattern="(.+) <(.+@.+)>"
		if [[ ! $PACKAGER =~ $packager_pattern ]]; then
			die "Invalid Packager format '${PACKAGER}' in makepkg.conf"
		fi

		PACKAGER_NAME=$(echo "${PACKAGER}"|sed -E "s/${packager_pattern}/\1/")
		PACKAGER_EMAIL=$(echo "${PACKAGER}"|sed -E "s/${packager_pattern}/\2/")

		if [[ ! $PACKAGER_EMAIL =~ .+@archlinux.org ]]; then
			die "Packager email '${PACKAGER_EMAIL}' is not an @archlinux.org address"
		fi
	fi

	msg "Collected packager settings"
	msg2 "name    : ${PACKAGER_NAME}"
	msg2 "email   : ${PACKAGER_EMAIL}"
	msg2 "gpg-key : ${GPGKEY:-undefined}"

	# TODO: print which protocol got auto detected, ssh https

	for path in "${paths[@]}"; do
		if ! realpath=$(realpath -e "${path}"); then
			error "No such directory: ${path}"
			continue
		fi

		pkgbase=$(basename "${realpath}")
		pkgbase=${pkgbase%.git}
		msg "Configuring ${pkgbase}"

		if [[ ! -d "${path}/.git" ]]; then
			error "Not a Git repository: ${path}"
			continue
		fi

		remote_url="${GIT_REPO_BASE_URL}/${pkgbase}.git"
		if ! git -C "${path}" remote add origin "${remote_url}" &>/dev/null; then
			git -C "${path}" remote set-url origin "${remote_url}"
		fi

		# move the master branch to main
		if [[ $(git -C "${path}" symbolic-ref --short HEAD) == master ]]; then
			git -C "${path}" branch --move main
			git -C "${path}" config branch.main.merge refs/heads/main
		fi

		git -C "${path}" config devtools.version "${GIT_REPO_SPEC_VERSION}"
		git -C "${path}" config pull.rebase true
		git -C "${path}" config branch.autoSetupRebase always
		git -C "${path}" config branch.main.remote origin
		git -C "${path}" config branch.main.rebase true

		git -C "${path}" config transfer.fsckobjects true
		git -C "${path}" config fetch.fsckobjects true
		git -C "${path}" config receive.fsckobjects true

		if (( ! UNPRIVILEGED )); then
			git -C "${path}" config user.name "${PACKAGER_NAME}"
			git -C "${path}" config user.email "${PACKAGER_EMAIL}"
			git -C "${path}" config commit.gpgsign true
			if [[ -n $GPGKEY ]]; then
				git -C "${path}" config user.signingKey "${GPGKEY}"
			else
				warning "Missing makepkg.conf configuration: GPGKEY"
			fi
		fi

		if ! git ls-remote origin &>/dev/null; then
			warning "configured remote origin may not exist, run:"
			msg2 "pkgctl repo create ${pkgbase}"
		fi
	done
}
