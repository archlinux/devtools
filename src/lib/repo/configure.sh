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
# shellcheck source=src/lib/util/git.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/git.sh

source /usr/share/makepkg/util/config.sh
source /usr/share/makepkg/util/message.sh

set -e
shopt -s nullglob


pkgctl_repo_configure_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PATH]...

		Configure Git packaging repositories according to distro specs and
		makepkg.conf settings.

		Git author information and the used signing key is set up from
		makepkg.conf read from any valid location like /etc or XDG_CONFIG_HOME.

		The remote protocol is automatically determined from the author email
		address by choosing SSH for all official packager identities and
		read-only HTTPS otherwise.

		Git default excludes and hooks are applied to the configured repo.

		OPTIONS
		    --protocol https     Configure remote url to use https
		    -j, --jobs N         Run up to N jobs in parallel (default: $(nproc))
		    -h, --help           Show this help text

		EXAMPLES
		    $ ${COMMAND} *
_EOF_
}

get_packager_name() {
	local packager=$1
	local packager_pattern="(.+) <(.+@.+)>"
	local name

	if [[ ! $packager =~ $packager_pattern ]]; then
		return 1
	fi

	name=$(echo "${packager}"|sed -E "s/${packager_pattern}/\1/")
	printf "%s" "${name}"
}

get_packager_email() {
	local packager=$1
	local packager_pattern="(.+) <(.+@.+)>"
	local email

	if [[ ! $packager =~ $packager_pattern ]]; then
		return 1
	fi

	email=$(echo "${packager}"|sed -E "s/${packager_pattern}/\2/")
	printf "%s" "${email}"
}

is_packager_name_valid() {
	local packager_name=$1
	if [[ -z ${packager_name} ]]; then
		return 1
	elif [[ ${packager_name} == "John Doe" ]]; then
		return 1
	elif [[ ${packager_name} == "Unknown Packager" ]]; then
		return 1
	fi
	return 0
}

is_packager_email_official() {
	local packager_email=$1
	if [[ -z ${packager_email} ]]; then
		return 1
	elif [[ $packager_email =~ .+@archlinux.org ]]; then
		return 0
	fi
	return 1
}

pkgctl_repo_configure() {
	# options
	local GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_HTTPS}
	local official=0
	local proto=https
	local proto_force=0
	local jobs=
	jobs=$(nproc)
	local paths=()

	# variables
	local -r command=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	local path realpath pkgbase remote_url project_path hook
	local PACKAGER GPGKEY packager_name packager_email

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_configure_usage
				exit 0
				;;
			--protocol=https)
				proto_force=1
				shift
				;;
			--protocol)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if [[ $2 == https ]]; then
					proto_force=1
				else
					die "unsupported protocol: %s" "$2"
				fi
				shift 2
				;;
			-j|--jobs)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				jobs=$2
				shift 2
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

	# Load makepkg.conf variables to be available for packager identity
	msg "Collecting packager identity from makepkg.conf"
	# shellcheck disable=2119
	load_makepkg_config
	if [[ -n ${PACKAGER} ]]; then
		if ! packager_name=$(get_packager_name "${PACKAGER}") || \
		   ! packager_email=$(get_packager_email "${PACKAGER}"); then
			die "invalid PACKAGER format '${PACKAGER}' in makepkg.conf"
		fi
		if ! is_packager_name_valid "${packager_name}"; then
			die "invalid PACKAGER '${PACKAGER}' in makepkg.conf"
		fi
		if is_packager_email_official "${packager_email}"; then
			official=1
			if (( ! proto_force )); then
				proto=ssh
				GIT_REPO_BASE_URL=${GIT_PACKAGING_URL_SSH}
			fi
		fi
	fi

	msg2 "name    : ${packager_name:-${YELLOW}undefined${ALL_OFF}}"
	msg2 "email   : ${packager_email:-${YELLOW}undefined${ALL_OFF}}"
	msg2 "gpg-key : ${GPGKEY:-${YELLOW}undefined${ALL_OFF}}"
	if [[ ${proto} == ssh ]]; then
		msg2 "protocol: ${GREEN}${proto}${ALL_OFF}"
	else
		msg2 "protocol: ${YELLOW}${proto}${ALL_OFF}"
	fi

	# parallelization
	if [[ ${jobs} != 1 ]] && (( ${#paths[@]} > 1 )); then
		if [[ -n ${BOLD} ]]; then
			export DEVTOOLS_COLOR=always
		fi

		# warm up ssh connection as it may require user input (key unlock, hostkey verification etc)
		if [[ ${proto} == ssh ]]; then
			git_warmup_ssh_connection
		fi

		if ! parallel --bar --jobs "${jobs}" "${command}" ::: "${paths[@]}"; then
			die 'Failed to configure some packages, please check the output'
			exit 1
		fi
		exit 0
	fi

	for path in "${paths[@]}"; do
		# resolve symlink for basename
		if ! realpath=$(realpath --canonicalize-existing -- "${path}"); then
			die "No such directory: ${path}"
		fi
		# skip paths that aren't directories
		if [[ ! -d "${realpath}" ]]; then
			continue
		fi

		pkgbase=$(basename "${realpath}")
		pkgbase=${pkgbase%.git}
		msg "Configuring ${pkgbase}"

		if [[ ! -d "${path}/.git" ]]; then
			die "Not a Git repository: ${path}"
		fi

		pushd "${path}" >/dev/null

		project_path=$(gitlab_project_name_to_path "${pkgbase}")
		remote_url="${GIT_REPO_BASE_URL}/${project_path}.git"
		if ! git remote add origin "${remote_url}" &>/dev/null; then
			git remote set-url origin "${remote_url}"
		fi

		# move the master branch to main
		if [[ $(git symbolic-ref --quiet --short HEAD) == master ]]; then
			git branch --move main
			git config branch.main.merge refs/heads/main
		fi

		# configure spec version and variant to avoid using development hooks in production
		git config devtools.version "${GIT_REPO_SPEC_VERSION}"
		if [[ ${_DEVTOOLS_LIBRARY_DIR} == /usr/share/devtools ]]; then
			git config devtools.variant canonical
		else
			warning "Configuring with development version of pkgctl, do not use this repo in production"
			git config devtools.variant development
		fi

		git config pull.rebase true
		git config branch.autoSetupRebase always
		git config branch.main.remote origin
		git config branch.main.rebase true

		git config transfer.fsckobjects true
		git config fetch.fsckobjects true
		git config receive.fsckobjects true

		# setup author identity
		if [[ -n ${packager_name} ]]; then
			git config user.name "${packager_name}"
			git config user.email "${packager_email}"
		fi

		# force gpg for official packagers
		if (( official )); then
			git config commit.gpgsign true
		fi

		# set custom pgp key from makepkg.conf
		if [[ -n $GPGKEY ]]; then
			git config commit.gpgsign true
			git config user.signingKey "${GPGKEY}"
		fi

		# set default git exclude
		mkdir -p .git/info
		ln -sf "${_DEVTOOLS_LIBRARY_DIR}/git.conf.d/template/info/exclude" \
			.git/info/exclude

		# set default git hooks
		mkdir -p .git/hooks
		rm -f .git/hooks/*.sample
		for hook in "${_DEVTOOLS_LIBRARY_DIR}"/git.conf.d/template/hooks/*; do
			ln -sf "${hook}" ".git/hooks/$(basename "${hook}")"
		done

		if ! git ls-remote origin &>/dev/null; then
			warning "configured remote origin may not exist, run:"
			msg2 "pkgctl repo create ${pkgbase}"
		fi

		popd >/dev/null
	done
}
