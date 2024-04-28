#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REPO_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REPO_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

set -e


pkgctl_repo_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]

		Manage Git packaging repositories and helps with their configuration
		according to distro specs.

		Git author information and the used signing key is set up from
		makepkg.conf read from any valid location like /etc or XDG_CONFIG_HOME.
		The configure command can be used to synchronize the distro specs and
		makepkg.conf settings for previously cloned repositories.

		The unprivileged option can be used for cloning packaging repositories
		without SSH access using read-only HTTPS.

		COMMANDS
		    clean          Remove untracked files from the working tree
		    clone          Clone a package repository
		    configure      Configure a clone according to distro specs
		    create         Create a new GitLab package repository
		    switch         Switch a package repository to a specified version
		    web            Open the packaging repository's website

		OPTIONS
		    -h, --help     Show this help text

		EXAMPLES
		    $ ${COMMAND} clean --interactive *
		    $ ${COMMAND} clone libfoo linux libbar
		    $ ${COMMAND} clone --maintainer mynickname
		    $ ${COMMAND} configure *
		    $ ${COMMAND} create libfoo
		    $ ${COMMAND} switch 2:1.19.5-1 libfoo
		    $ ${COMMAND} web linux
_EOF_
}

pkgctl_repo() {
	if (( $# < 1 )); then
		pkgctl_repo_usage
		exit 0
	fi

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_repo_usage
				exit 0
				;;
			clean)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/repo/clean.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/clean.sh
				pkgctl_repo_clean "$@"
				exit 0
				;;
			clone)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/repo/clone.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/clone.sh
				pkgctl_repo_clone "$@"
				exit 0
				;;
			configure)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/repo/configure.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/configure.sh
				pkgctl_repo_configure "$@"
				exit 0
				;;
			create)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/repo/create.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/create.sh
				pkgctl_repo_create "$@"
				exit 0
				;;
			switch)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/repo/switch.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/switch.sh
				pkgctl_repo_switch "$@"
				exit 0
				;;
			web)
				_DEVTOOLS_COMMAND+=" $1"
				shift
				# shellcheck source=src/lib/repo/web.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/web.sh
				pkgctl_repo_web "$@"
				exit 0
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				die "invalid command: %s" "$1"
				;;
		esac
	done
}
