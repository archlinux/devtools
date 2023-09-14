#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_REBUILD_TODO_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_REBUILD_TODO_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}

source /usr/share/makepkg/util/util.sh

# shellcheck source=src/lib/repo/clone.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/repo/clone.sh
# shellcheck source=src/lib/build/build.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/build/build.sh
# shellcheck source=src/lib/release.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/release.sh

set -e


pkgctl_rebuild_todo_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] URL

		Rebuilds packages from a todo list.

		OPTIONS
		    -h, --help        Show this help text
		    -m, --message MSG Use the given <msg> as the commit message
		    -i, --ignore      Give one or more pkgbases to ignore
		    -f, --maintainer  Filter for one or more maintainers (orphan for orphan packages)
		    -o, --offload     Build on a remote server and transfer artifacts afterwards
		    -e, --edit        Edit PKGBUILD before building. Default when todo type is "Task"
		    -r, --repo REPO   Specify a target repository (disables auto-detection)
		    -s, --staging     Release to the staging counterpart of the auto-detected repo
		    -t, --testing     Release to the testing counterpart of the auto-detected repo
		    -u, --db-update   Automatically update the pacman database after uploading
		    --no-build        Don't build PKGBUILD
		    --no-release      Don't run commitpkg after building

		EXAMPLES
			TODO
_EOF_
}

pkgctl_rebuild_todo() {
	if (( $# < 1 )); then
		pkgctl_rebuild_todo_usage
		exit 1
	fi

	local URL=""
	local REPO=""

	local MAINTAINERS=()
	local IGNORE_PKGBASES=()
	local FILTER_REPOSITORY=("extra")

	local DRY_RUN=0
	local MESSAGE_SET=0
	local NO_RELEASE=0
	local NO_BUILD=0

	local RELEASE_OPTIONS=("--staging")
	local BUILD_OPTIONS=("--staging" "--rebuild")

	local packages

	# option checking
	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_rebuild_todo_usage
				exit 0
				;;
			--dry-run)
				DRY_RUN=1
				shift 1
				;;
			-f|--maintainer)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				MAINTAINERS+=("$2")
				shift 2
				;;
			-i|--ignore)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				IGNORE_PKGBASES+=("$2")
				shift 2
				;;
			-o|--offload)
				BUILD_OPTIONS+=("--offload")
				shift
				;;
			-e|--edit)
				BUILD_OPTIONS+=("--edit")
				shift
				;;
			-m|--message)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				MESSAGE_SET=1
				RELEASE_OPTIONS+=("--message" "$2")
				shift 2
				;;
			-s|--staging)
				RELEASE_OPTIONS+=("--staging")
				shift
				;;
			-t|--testing)
				RELEASE_OPTIONS+=("--testing")
				shift
				;;
			--no-release)
				NO_RELEASE=1
				shift
				;;
			--no-build)
				NO_BUILD=1
				shift
				;;
			-*)
				die "invalid option: %s" "$1"
				;;
			*)
				if [[ ! "$1" == https* ]]; then
					die "Missing url!"
				fi
				URL="$1"
				if [[ ! "$URL" == */ ]]; then
					URL+="/"
				fi
				if [[ ! "$URL" == *json ]]; then
					URL+="json"
				fi
				break
				;;
		esac
	done

	# TODO: setup default values for options

	while read -r json; do
		readarray -t packages < <(jq --slurpfile repo <(printf '"%s" ' "${FILTER_REPOSITORY[@]}") \
									 --slurpfile maint <(printf '"%s" ' "${MAINTAINERS[@]}") \
									 -r '.created as $created
										 | .packages[]
										 | select(.status_str == "Incomplete" )
										 | select([.repo] | inside($repo))
										 | select(($maint[0] == "") or (($maint[0] == "orphan") and .maintainers == []) or (select(.maintainers | any([.] | inside($maint)))))
										 | "\(.pkgbase)"' \
									 - <<< "$json" | sort -u)

		# This removes any elements we have ignored.... it's not pretty
		readarray -t packages < <(comm -1 -3 <(printf "%s\n" "${IGNORE_PKGBASES[@]}" | sort) <(printf "%s\n" "${packages[@]}"| sort))

		# Default to include the list name in the commit message
		if (( ! MESSAGE_SET )); then
			RELEASE_OPTIONS+=("--message" "$(jq -r '.name' - <<< "$json")")
		fi

		# If we are doing a Task we probably want to edit the PKGBUILD
		if [[ "$(jq -r '.kind' - <<< "$json")" == "Task" ]]; then
			BUILD_OPTIONS+=("--edit")
		fi
	done <<< "$(curl -s "$URL")"

	if (( DRY_RUN )); then
		msg "Would rebuild the following packages:"
		msg2 '%s' "${packages[@]}"
		msg "by running the following for each:"
		if ! ((NO_BUILD)); then
			msg2 "pkgctl build ${BUILD_OPTIONS[*]}"
		fi
		if ! ((NO_RELEASE)); then
			msg2 "pkgctl release ${RELEASE_OPTIONS[*]}"
		fi
		exit 0
	fi

	if (( 0 == ${#packages[@]} )); then
		die "No packages to rebuild!"
	fi

	msg "Rebuilding the following packages:"
	msg2 '%s' "${packages[@]}"
	msg "Press [Enter] to continue..."
	read <&1

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	pushd "$WORKDIR" &>/dev/null

	# TODO set -j 1 to circumvent bug in repo clone
	msg "Clone the pacakges"
	if ! pkgctl_repo_clone -j 1 "${packages[@]}"; then
		die "error while cloning packages"
	fi

	for pkg in "${packages[@]}"; do
		pushd "$pkg" &>/dev/null

		# This should help us figure out if the package is already built
		readarray -t pkgs < <(makepkg --packagelist)
		if [[ -f ${pkgs[0]} ]]; then
			msg "${pkg[0]} has already been rebuilt!"
			continue
		fi

		if ! ((NO_BUILD)); then
			SKIP_BUILD=0
			while true; do
				# TODO: it seems like pkgctl build does not set the exit code correctly if (offload?) build fails
				if pkgctl_build "${BUILD_OPTIONS[@]}"; then
					break
				fi
				error "We failed to build! You are in a subshell to fix the build. Exit the shell to build again."
				$SHELL || true
				read -p "Skip build? [N/y] " -n 1 -r
				if [[ $REPLY =~ ^[Yy]$ ]]; then
					SKIP_BUILD=1
					break
				fi
			done
			if ((SKIP_BUILD)); then
				popd &>/dev/null
				continue
			fi
		fi
		if ! ((NO_RELEASE)); then
			pkgctl_release "${RELEASE_OPTIONS[@]}"
		fi
		popd &>/dev/null
	done
}
