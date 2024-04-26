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
# shellcheck source=src/lib/util/srcinfo.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/srcinfo.sh
# shellcheck source=src/lib/util/pacman.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pacman.sh
# shellcheck source=src/lib/util/pkgbuild.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pkgbuild.sh
# shellcheck source=src/lib/valid-build-install.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-build-install.sh
# shellcheck source=src/lib/valid-repos.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-repos.sh
# shellcheck source=src/lib/valid-tags.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-tags.sh
# shellcheck source=src/lib/valid-inspect.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/valid-inspect.sh

source /usr/share/makepkg/util/config.sh
source /usr/share/makepkg/util/message.sh

set -eo pipefail


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
		    --repo REPO          Specify target repository for new packages not in any official repo
		    -s, --staging        Build against the staging counterpart of the auto-detected repo
		    -t, --testing        Build against the testing counterpart of the auto-detected repo
		    -o, --offload        Build on a remote server and transfer artifacts afterwards
		    -c, --clean          Recreate the chroot before building
		    --inspect WHEN       Spawn an interactive shell to inspect the chroot (never, always, failure)
		    -w, --worker SLOT    Name of the worker slot, useful for concurrent builds (disables automatic names)
		    --nocheck            Do not run the check() function in the PKGBUILD

		INSTALL OPTIONS
		    -I, --install-to-chroot FILE   Install a package to the working copy of the chroot
		    -i, --install-to-host MODE     Install the built package to the host system, possible modes are 'all' and 'auto'

		PKGBUILD OPTIONS
		    --pkgver=PKGVER      Set pkgver, reset pkgrel and update checksums
		    --pkgrel=PKGREL      Set pkgrel to a given value
		    --rebuild            Increment the current pkgrel variable
		    --update-checksums   Force computation and update of the checksums (disables auto-detection)
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
	if [[ -n "${repo}" ]] || (( testing )) || (( staging )); then
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

	local UPDATE_CHECKSUMS=0
	local EDIT=0
	local REBUILD=0
	local OFFLOAD=0
	local STAGING=0
	local TESTING=0
	local RELEASE=0
	local DB_UPDATE=0
	local INSTALL_TO_HOST=none

	local REPO=
	local PKGVER=
	local PKGREL=
	local MESSAGE=

	local paths=()
	local BUILD_ARCH=()
	local BUILD_OPTIONS=()
	local MAKECHROOT_OPTIONS=()
	local RELEASE_OPTIONS=()
	local MAKEPKG_OPTIONS=()
	local INSTALL_HOST_PACKAGES=()

	local WORKER=
	local WORKER_SLOT=

	# variables
	local _arch path pkgbase pkgrepo source pkgbuild_checksum current_checksum

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_build_usage
				exit 0
				;;
			--repo)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				pkgctl_build_check_option_group_repo '--repo' "${REPO}" "${TESTING}" "${STAGING}"
				REPO="${2}"
				RELEASE_OPTIONS+=("--repo" "${REPO}")
				shift 2
				;;
			--arch)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if [[ ${2} == all ]]; then
					BUILD_ARCH=("${DEVTOOLS_VALID_ARCHES[@]::${#DEVTOOLS_VALID_ARCHES[@]}-1}")
				elif [[ ${2} == any ]]; then
					BUILD_ARCH=("${DEVTOOLS_VALID_ARCHES[0]}")
				elif ! in_array "${2}" "${BUILD_ARCH[@]}"; then
					if ! in_array "${2}" "${DEVTOOLS_VALID_ARCHES[@]}"; then
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
				UPDATE_CHECKSUMS=1
				shift
				;;
			--pkgrel=*)
				pkgctl_build_check_option_group_ver '--pkgrel' "${PKGVER}" "${PKGREL}" "${REBUILD}"
				PKGREL="${1#*=}"
				shift
				;;
			--update-checksums)
				UPDATE_CHECKSUMS=1
				shift
				;;
			--rebuild)
				# shellcheck source=src/lib/util/git.sh
				source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/git.sh
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
				pkgctl_build_check_option_group_repo '--staging' "${REPO}" "${TESTING}" "${STAGING}"
				STAGING=1
				RELEASE_OPTIONS+=("--staging")
				shift
				;;
			-t|--testing)
				pkgctl_build_check_option_group_repo '--testing' "${REPO}" "${TESTING}" "${STAGING}"
				TESTING=1
				RELEASE_OPTIONS+=("--testing")
				shift
				;;
			-c|--clean)
				BUILD_OPTIONS+=("-c")
				shift
				;;
			-I|--install-to-chroot)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if (( OFFLOAD )); then
					MAKECHROOT_OPTIONS+=("-I" "$2")
				else
					MAKECHROOT_OPTIONS+=("-I" "$(realpath "$2")")
				fi
				warning 'installing packages to the chroot may break reproducible builds, use with caution!'
				shift 2
				;;
			-i|--install-to-host)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! in_array "$2" "${DEVTOOLS_VALID_BUILD_INSTALL[@]}"; then
					die 'invalid install mode: %s' "${2}"
				fi
				INSTALL_TO_HOST=$2
				shift 2
				;;
			--nocheck)
				MAKEPKG_OPTIONS+=("--nocheck")
				warning 'not running checks is disallowed for official packages, except for bootstrapping. Please rebuild after bootstrapping is completed!'
				shift
				;;
			--inspect)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				if ! in_array "${2}" "${DEVTOOLS_VALID_INSPECT_MODES[@]}"; then
					die "Invalid inspect mode: %s" "${2}"
				fi
				MAKECHROOT_OPTIONS+=("-x" "${2}")
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
			-w|--worker)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				WORKER_SLOT=$2
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

	# check if any release specific options were specified without releasing
	if (( ! RELEASE )); then
		if (( DB_UPDATE )); then
			die "cannot use --db-update without --release"
		fi
		if [[ -n "${MESSAGE}" ]]; then
			die "cannot use --message without --release"
		fi
	fi

	# check if invoked without any path from within a packaging repo
	if (( ${#paths[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			paths=(".")
		else
			pkgctl_build_usage
			exit 1
		fi
	fi

	# assign default worker slot
	if [[ -z ${WORKER_SLOT} ]] && ! WORKER_SLOT="$(tty | sed 's|/dev/pts/||')"; then
		WORKER_SLOT=$(( RANDOM % $(nproc) + 1 ))
	fi
	WORKER="${USER}-${WORKER_SLOT}"

	# Update pacman cache for auto-detection
	if [[ -z ${REPO} ]]; then
		update_pacman_repo_cache multilib
	# Check valid repos if not resolved dynamically
	elif ! in_array "${REPO}" "${DEVTOOLS_VALID_REPOS[@]}"; then
		die "Invalid repository target: %s" "${REPO}"
	fi

	for path in "${paths[@]}"; do
		# skip paths that are not directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi
		pushd "${path}" >/dev/null

		if [[ ! -f PKGBUILD ]]; then
			die 'PKGBUILD not found in %s' "${path}"
		fi

		source=()
		# shellcheck source=contrib/makepkg/PKGBUILD.proto
		. ./PKGBUILD
		pkgbase=${pkgbase:-$pkgname}
		pkgrepo=${REPO}
		pkgbuild_checksum=$(b2sum PKGBUILD | awk '{print $1}')
		msg "Building ${pkgbase}"

		# auto-detect target repository
		if ! repo=$(get_pacman_repo_from_pkgbuild PKGBUILD); then
			die 'Failed to query pacman repo'
		fi

		# fail if an existing package specifies --repo
		if [[ -n "${repo}" ]] && [[ -n ${pkgrepo} ]]; then
			# allow unstable to use --repo
			if [[ ${pkgrepo} == *unstable ]]; then
				repo=${pkgrepo}
			else
				die 'Using --repo for packages that exist in official repositories is disallowed'
			fi
		fi

		# assign auto-detected target repository
		if [[ -n ${repo} ]]; then
			pkgrepo=${repo}
		# fallback to extra for unreleased packages
		elif [[ -z ${pkgrepo} ]]; then
			pkgrepo=extra
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
				BUILD_ARCH=("${DEVTOOLS_VALID_ARCHES[0]}")
			else
				for _arch in "${arch[@]}"; do
					if in_array "${_arch}" "${DEVTOOLS_VALID_ARCHES[@]}"; then
						BUILD_ARCH+=("$_arch")
					else
						warning 'invalid architecture, not building for: %s' "${_arch}"
					fi
				done
			fi
		fi

		# print gathered build modes
		msg2 "  repo: ${pkgrepo}"
		msg2 "  arch: ${BUILD_ARCH[*]}"
		msg2 "worker: ${WORKER}"

		# increment pkgrel on rebuild
		if (( REBUILD )); then
			# try to figure out if pkgrel has been changed
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
			msg "Bumping pkgver to ${PKGVER}"
			pkgbuild_set_pkgver "${PKGVER}"
		fi

		# update pkgrel
		if [[ -n ${PKGREL} ]]; then
			msg "Bumping pkgrel to ${PKGREL}"
			pkgbuild_set_pkgrel "${PKGREL}"
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
		if (( UPDATE_CHECKSUMS )) && (( ${#source[@]} >= 1 )); then
			if ! result=$(pkgbuild_update_checksums /dev/stderr); then
				die "${result}"
			fi
		fi

		# re-source the PKGBUILD if it changed
		current_checksum="$(b2sum PKGBUILD | awk '{print $1}')"
		if [[ ${pkgbuild_checksum} != "${current_checksum}" ]]; then
			pkgbuild_checksum=${current_checksum}
			# shellcheck source=contrib/makepkg/PKGBUILD.proto
			. ./PKGBUILD
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
				offload-build --repo "${pkgrepo}" -- "${BUILD_OPTIONS[@]}" -- "${MAKECHROOT_OPTIONS[@]}" -l "${WORKER}" -- "${MAKEPKG_OPTIONS[@]}"
			else
				"${BUILDTOOL}" "${BUILD_OPTIONS[@]}" -- "${MAKECHROOT_OPTIONS[@]}" -l "${WORKER}" -- "${MAKEPKG_OPTIONS[@]}"
			fi
		done

		# re-source the PKGBUILD if it changed
		current_checksum="$(b2sum PKGBUILD | awk '{print $1}')"
		if [[ ${pkgbuild_checksum} != "${current_checksum}" ]]; then
			pkgbuild_checksum=${current_checksum}
			# shellcheck source=contrib/makepkg/PKGBUILD.proto
			. ./PKGBUILD
		fi

		# auto generate .SRCINFO
		# shellcheck disable=SC2119
		write_srcinfo_file

		# test-install (some of) the produced packages
		if [[ ${INSTALL_TO_HOST} == auto ]] || [[ ${INSTALL_TO_HOST} == all ]]; then
			# shellcheck disable=2119
			load_makepkg_config

			# this is inspired by print_all_package_names from libmakepkg
			local version pkg_architecture pkg pkgfile
			version=$(get_full_version)

			for pkg in "${pkgname[@]}"; do
				pkg_architecture=$(get_pkg_arch "$pkg")
				pkgfile=$(realpath "$(printf "%s/%s-%s-%s%s\n" "${PKGDEST:-.}" "$pkg" "$version" "$pkg_architecture" "$PKGEXT")")

				# check if we install all packages or if the (split-)package is already installed
				if [[ ${INSTALL_TO_HOST} == all ]] || ( [[ ${INSTALL_TO_HOST} == auto ]] && pacman -Qq -- "$pkg" &>/dev/null ); then
					INSTALL_HOST_PACKAGES+=("$pkgfile")
				fi
			done
		fi

		# release the build
		if (( RELEASE )); then
			pkgctl_release "${RELEASE_OPTIONS[@]}"
		fi

		# reset common PKGBUILD variables
		unset pkgbase pkgname arch pkgrepo source pkgver pkgrel validpgpkeys
		popd >/dev/null
	done

	# install all collected packages to the host system
	if (( ${#INSTALL_HOST_PACKAGES[@]} )); then
		msg "Installing built packages to the host system"
		sudo pacman -U -- "${INSTALL_HOST_PACKAGES[@]}"
	fi

	# update the binary package repo db as last action
	if (( RELEASE )) && (( DB_UPDATE )); then
		# shellcheck disable=2119
		pkgctl_db_update
	fi
}
