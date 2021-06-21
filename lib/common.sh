#!/hint/bash
# This may be included with or without `set -euE`

# License: Unspecified

[[ -z ${_INCLUDE_COMMON_SH:-} ]] || return 0
_INCLUDE_COMMON_SH="$(set +o|grep nounset)"

set +u +o posix
# shellcheck disable=1091
. /usr/share/makepkg/util.sh
$_INCLUDE_COMMON_SH

# Avoid any encoding problems
export LANG=C

# Set buildtool properties
export BUILDTOOL=devtools
export BUILDTOOLVER=m4_devtools_version

shopt -s extglob

# check if messages are to be printed using color
if [[ -t 2 && "$TERM" != dumb ]]; then
	colorize
else
	# shellcheck disable=2034
	declare -gr ALL_OFF='' BOLD='' BLUE='' GREEN='' RED='' YELLOW=''
fi

stat_busy() {
	local mesg=$1; shift
	# shellcheck disable=2059
	printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}...${ALL_OFF}" "$@" >&2
}

stat_done() {
	# shellcheck disable=2059
	printf "${BOLD}done${ALL_OFF}\n" >&2
}

_setup_workdir=false
setup_workdir() {
	[[ -z ${WORKDIR:-} ]] && WORKDIR=$(mktemp -d --tmpdir "${0##*/}.XXXXXXXXXX")
	_setup_workdir=true
	trap 'trap_abort' INT QUIT TERM HUP
	trap 'trap_exit' EXIT
}

cleanup() {
	if [[ -n ${WORKDIR:-} ]] && $_setup_workdir; then
		rm -rf "$WORKDIR"
	fi
	exit "${1:-0}"
}

abort() {
	error 'Aborting...'
	cleanup 255
}

trap_abort() {
	trap - EXIT INT QUIT TERM HUP
	abort
}

trap_exit() {
	local r=$?
	trap - EXIT INT QUIT TERM HUP
	cleanup $r
}

die() {
	(( $# )) && error "$@"
	cleanup 255
}

##
#  usage : lock( $fd, $file, $message, [ $message_arguments... ] )
##
lock() {
	# Only reopen the FD if it wasn't handed to us
	if ! [[ "/dev/fd/$1" -ef "$2" ]]; then
		mkdir -p -- "$(dirname -- "$2")"
		eval "exec $1>"'"$2"'
	fi

	if ! flock -n "$1"; then
		stat_busy "${@:3}"
		flock "$1"
		stat_done
	fi
}

##
#  usage : slock( $fd, $file, $message, [ $message_arguments... ] )
##
slock() {
	# Only reopen the FD if it wasn't handed to us
	if ! [[ "/dev/fd/$1" -ef "$2" ]]; then
		mkdir -p -- "$(dirname -- "$2")"
		eval "exec $1>"'"$2"'
	fi

	if ! flock -sn "$1"; then
		stat_busy "${@:3}"
		flock -s "$1"
		stat_done
	fi
}

##
#  usage : lock_close( $fd )
##
lock_close() {
	local fd=$1
	# https://github.com/koalaman/shellcheck/issues/862
	# shellcheck disable=2034
	exec {fd}>&-
}

##
# usage: pkgver_equal( $pkgver1, $pkgver2 )
##
pkgver_equal() {
	if [[ $1 = *-* && $2 = *-* ]]; then
		# if both versions have a pkgrel, then they must be an exact match
		[[ $1 = "$2" ]]
	else
		# otherwise, trim any pkgrel and compare the bare version.
		[[ ${1%%-*} = "${2%%-*}" ]]
	fi
}

##
#  usage: find_cached_package( $pkgname, $pkgver, $arch )
#
#    $pkgver can be supplied with or without a pkgrel appended.
#    If not supplied, any pkgrel will be matched.
##
find_cached_package() {
	local searchdirs=("$PWD" "$PKGDEST") results=()
	local targetname=$1 targetver=$2 targetarch=$3
	local dir pkg pkgbasename name ver rel arch r results

	for dir in "${searchdirs[@]}"; do
		[[ -d $dir ]] || continue

		for pkg in "$dir"/*.pkg.tar?(.!(sig|*.*)); do
			[[ -f $pkg ]] || continue

			# avoid adding duplicates of the same inode
			for r in "${results[@]}"; do
				[[ $r -ef $pkg ]] && continue 2
			done

			# split apart package filename into parts
			pkgbasename=${pkg##*/}
			pkgbasename=${pkgbasename%.pkg.tar*}

			arch=${pkgbasename##*-}
			pkgbasename=${pkgbasename%-"$arch"}

			rel=${pkgbasename##*-}
			pkgbasename=${pkgbasename%-"$rel"}

			ver=${pkgbasename##*-}
			name=${pkgbasename%-"$ver"}

			if [[ $targetname = "$name" && $targetarch = "$arch" ]] &&
					pkgver_equal "$targetver" "$ver-$rel"; then
				results+=("$pkg")
			fi
		done
	done

	case ${#results[*]} in
		0)
			return 1
			;;
		1)
			printf '%s\n' "${results[0]}"
			return 0
			;;
		*)
			error 'Multiple packages found:'
			printf '\t%s\n' "${results[@]}" >&2
			return 1
	esac
}
