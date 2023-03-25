#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_BUILD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_BUILD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/db/update.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/db/update.sh
# shellcheck source=src/lib/release.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/release.sh
# shellcheck source=src/lib/util/git.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/git.sh
# shellcheck source=src/lib/util/pacman.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pacman.sh
# shellcheck source=src/lib/valid-repos.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-repos.sh
# shellcheck source=src/lib/valid-tags.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-tags.sh

source /usr/share/makepkg/util/config.sh
source /usr/share/makepkg/util/message.sh

set -e


pkgctl_build_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
    cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PATH]...

		Build packages inside a clean chroot

		When a new pkgver is set using the appropriate PKGBUILD options the
		checksums are automatically updated.

		TODO

		BUILD OPTIONS
		    --arch ARCH          Specify architectures to build for (disables auto-detection)
		    --repo REPO          Specify a target repository (disables auto-detection)
		    -s, --staging        Build against the staging counterpart of the auto-detected repo
		    -t, --testing        Build against the testing counterpart of the auto-detected repo
		    -o, --offload        Build on a remote server and transfer artifacts afterwards
		    -c, --clean          Recreate the chroot before building
		    -I, --install FILE   Install a package into the working copy of the chroot

		PKGBUILD OPTIONS
		    --pkgver=PKGVER      Set pkgver, reset pkgrel and update checksums
		    --pkgrel=PKGREL      Set pkgrel to a given value
		    --rebuild            Increment the current pkgrel variable
		    -e, --edit           Edit the PKGBUILD before building

		RELEASE OPTIONS
		    -r, --release        Automatically commit, tag and release after building
		    -m, --message MSG    Use the given <msg> as the commit message
		    -u, --db-update      Automatically update the pacman database as last action

		OPTIONS
		    -h, --help           Show this help text

		EXAMPLES
		    $ ${COMMAND}
		    $ ${COMMAND} --rebuild --staging --message 'libyay 0.42 rebuild' libfoo libbar
		    $ ${COMMAND} --pkgver 1.42 --release --db-update
_EOF_
}

pkgctl_build_check_option_group_repo() {
	local option=$1
	local repo=$2
	local testing=$3
	local staging=$4
	if ( (( testing )) && (( staging )) ) ||
		( [[ $repo =~ ^.*-(staging|testing)$ ]] && ( (( testing )) || (( staging )) )); then
		die "The argument '%s' cannot be used with one or more of the other specified arguments" "${option}"
		exit 1
	fi
	return 0
}

pkgctl_build_check_option_group_ver() {
	local option=$1
	local pkgver=$2
	local pkgrel=$3
	local rebuild=$4
	if [[ -n "${pkgver}" ]] || [[ -n "${pkgrel}" ]] || (( rebuild )); then
		die "The argument '%s' cannot be used with one or more of the other specified arguments" "${option}"
		exit 1
	fi
	return 0
}

# TODO: import pgp keys
pkgctl_build() {
	if (( $# < 1 )) && [[ ! -f PKGBUILD ]]; then
		pkgctl_build_usage
		exit 1
	fi

	local UPDPKGSUMS=0
	local EDIT=0
	local REBUILD=0
	local OFFLOAD=0
	local STAGING=0
	local TESTING=0
	local RELEASE=0
	local DB_UPDATE=0

	local REPO=
	local PKGVER=
	local PKGREL=
	local MESSAGE=

	local paths=()
	local BUILD_ARCH=()
	local BUILD_OPTIONS=()
	local MAKECHROOT_OPTIONS=()
	local RELEASE_OPTIONS=()

	local PTS
	PTS="$(tty | sed 's|/dev/pts/||')"
	local WORKER="${USER}-${PTS}"

	# variables
	local path pkgbase pkgrepo source

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_build_usage
				exit 0
				;;
			--repo)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				REPO="${2}"
				pkgctl_build_check_option_group_repo '--repo' "${REPO}" "${TESTING}" "${STAGING}"
				shift 2
				;;
			--arch)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if [[ ${2} == all ]]; then
					BUILD_ARCH=("${_arch[@]::${#_arch[@]}-1}")
				elif [[ ${2} == any ]]; then
					BUILD_ARCH=("${_arch[0]}")
				elif ! in_array "${2}" "${BUILD_ARCH[@]}"; then
					if ! in_array "${2}" "${_arch[@]}"; then
						die 'invalid architecture: %s' "${2}"
					fi
					BUILD_ARCH+=("${2}")
				fi
				shift 2
				;;
			--pkgver=*)
				pkgctl_build_check_option_group_ver '--pkgver' "${PKGVER}" "${PKGREL}" "${REBUILD}"
				PKGVER="${1#*=}"
				PKGREL=1
				UPDPKGSUMS=1
				shift
				;;
			--pkgrel=*)
				pkgctl_build_check_option_group_ver '--pkgrel' "${PKGVER}" "${PKGREL}" "${REBUILD}"
				PKGREL="${1#*=}"
				shift
				;;
			--rebuild)
				pkgctl_build_check_option_group_ver '--rebuild' "${PKGVER}" "${PKGREL}" "${REBUILD}"
				REBUILD=1
				shift
				;;
			-e|--edit)
				EDIT=1
				shift
				;;
			-o|--offload)
				OFFLOAD=1
				shift
				;;
			-s|--staging)
				STAGING=1
				pkgctl_build_check_option_group_repo '--staging' "${REPO}" "${TESTING}" "${STAGING}"
				shift
				;;
			-t|--testing)
				TESTING=1
				pkgctl_build_check_option_group_repo '--testing' "${REPO}" "${TESTING}" "${STAGING}"
				shift
				;;
			-c|--clean)
				BUILD_OPTIONS+=("-c")
				shift
				;;
			-I|--install)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				MAKECHROOT_OPTIONS+=("-I" "$2")
				warning 'installing packages into the chroot may break reproducible builds, use with caution!'
				shift 2
				;;
			-r|--release)
				# shellcheck source=src/lib/release.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/release.sh
				RELEASE=1
				shift
				;;
			-m|--message)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				MESSAGE=$2
				RELEASE_OPTIONS+=("--message" "${MESSAGE}")
				shift 2
				;;
			-u|--db-update)
				DB_UPDATE=1
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
			pkgctl_build_usage
			exit 1
		fi
	fi

	# Update pacman cache for auto-detection
	if [[ -z ${REPO} ]]; then
		update_pacman_repo_cache
	# Check valid repos if not resolved dynamically
	elif ! in_array "${REPO}" "${_repos[@]}"; then
		die "Invalid repository target: %s" "${REPO}"
	fi

	for path in "${paths[@]}"; do
		pushd "${path}" >/dev/null

		if [[ ! -f PKGBUILD ]]; then
			die 'PKGBUILD not found in %s' "${path}"
		fi

		source=()
		# shellcheck source=contrib/makepkg/PKGBUILD.proto
		. ./PKGBUILD
		pkgbase=${pkgbase:-$pkgname}
		pkgrepo=${REPO}
		msg "Building ${pkgbase}"

		# auto-detection of build target
		if [[ -z ${pkgrepo} ]]; then
			if ! pkgrepo=$(get_pacman_repo_from_pkgbuild PKGBUILD); then
				die 'failed to get pacman repo'
			fi
			if [[ -z "${pkgrepo}" ]]; then
				die 'unknown repo, please specify --repo for new packages'
			fi
		fi

		# special cases to resolve final build target
		if (( TESTING )); then
			pkgrepo="${pkgrepo}-testing"
		elif (( STAGING )); then
			pkgrepo="${pkgrepo}-staging"
		elif [[ $pkgrepo == core ]]; then
			pkgrepo="${pkgrepo}-testing"
		fi

		# auto-detection of build architecture
		if [[ $pkgrepo = multilib* ]]; then
			BUILD_ARCH=("")
		elif (( ${#BUILD_ARCH[@]} == 0 )); then
			if in_array any "${arch[@]}"; then
				BUILD_ARCH=("${_arch[0]}")
			else
				BUILD_ARCH+=("${arch[@]}")
			fi
		fi

		# print gathered build modes
		msg2 "repo: ${pkgrepo}"
		msg2 "arch: ${BUILD_ARCH[*]}"

		# increment pkgrel on rebuild
		if (( REBUILD )); then
			# try to figure out of pkgrel has been changed
			if ! old_pkgrel=$(git_diff_tree HEAD PKGBUILD | grep --perl-regexp --only-matching --max-count=1 '^-pkgrel=\K\w+'); then
				old_pkgrel=${pkgrel}
			fi
			# check if pkgrel conforms expectations
			[[ ${pkgrel/.*} =~ ^[0-9]+$ ]] || die "Non-standard pkgrel declaration"
			[[ ${old_pkgrel/.*} =~ ^[0-9]+$ ]] || die "Non-standard pkgrel declaration"
			# increment pkgrel if it hasn't been changed yet
			if [[ ${pkgrel} = "${old_pkgrel}" ]]; then
				PKGREL=$((${pkgrel/.*}+1))
			else
				warning 'ignoring --rebuild as pkgrel has already been incremented from %s to %s' "${old_pkgrel}" "${pkgrel}"
			fi
		fi

		# update pkgver
		if [[ -n ${PKGVER} ]]; then
			if [[ $(type -t pkgver) == function ]]; then
				# TODO: check if die or warn, if we provide _commit _gitcommit setter maybe?
				warning 'setting pkgver variable has no effect if the PKGBUILD has a pkgver() function'
			fi
			msg "Bumping pkgver to ${PKGVER}"
			grep --extended-regexp --quiet --max-count=1 "^pkgver=${pkgver}$" PKGBUILD || die "Non-standard pkgver declaration"
			sed --regexp-extended "s|^(pkgver=)${pkgver}$|\1${PKGVER}|g" -i PKGBUILD
		fi

		# update pkgrel
		if [[ -n ${PKGREL} ]]; then
			msg "Bumping pkgrel to ${PKGREL}"
			grep --extended-regexp --quiet --max-count=1 "^pkgrel=${pkgrel}$" PKGBUILD || die "Non-standard pkgrel declaration"
			sed --regexp-extended "s|^(pkgrel=)${pkgrel}$|\1${PKGREL}|g" -i PKGBUILD
		fi

		# edit PKGBUILD
		if (( EDIT )); then
			stat_busy 'Editing PKGBUILD'
			if [[ -n $GIT_EDITOR ]]; then
				$GIT_EDITOR PKGBUILD || die
			elif [[ -n $VISUAL ]]; then
				$VISUAL PKGBUILD || die
			elif [[ -n $EDITOR ]]; then
				$EDITOR PKGBUILD || die
			elif giteditor=$(git config --get core.editor); then
				$giteditor PKGBUILD || die
			else
				die "No usable editor found (tried \$GIT_EDITOR, \$VISUAL, \$EDITOR, git config [core.editor])."
			fi
			stat_done
		fi


		# update checksums if any sources are declared
		if (( UPDPKGSUMS )) && (( ${#source[@]} >= 1 )); then
			updpkgsums
		fi

		# execute build
		for arch in "${BUILD_ARCH[@]}"; do
			if [[ -n $arch ]]; then
				msg "Building ${pkgbase} for [${pkgrepo}] (${arch})"
				BUILDTOOL="${pkgrepo}-${arch}-build"
			else
				msg "Building ${pkgbase} for [${pkgrepo}]"
				BUILDTOOL="${pkgrepo}-build"
			fi

			if (( OFFLOAD )); then
				offload-build --repo "${pkgrepo}" -- "${BUILD_OPTIONS[@]}" -- "${MAKECHROOT_OPTIONS[@]}" -l "${WORKER}"
			else
				"${BUILDTOOL}" "${BUILD_OPTIONS[@]}" -- "${MAKECHROOT_OPTIONS[@]}" -l "${WORKER}"
			fi
		done

		# release the build
		if (( RELEASE )); then
			pkgctl_release --repo "${pkgrepo}" "${RELEASE_OPTIONS[@]}"
		fi

		# reset common PKGBUILD variables
		unset pkgbase pkgname arch pkgrepo source pkgver pkgrel validpgpkeys
		popd >/dev/null
	done

	# update the binary package repo db as last action
	if (( RELEASE )) && (( DB_UPDATE )); then
		# shellcheck disable=2119
		pkgctl_db_update
	fi
}
