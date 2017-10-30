#!/hint/bash
# License: Unspecified
:

# shellcheck disable=2034
CHROOT_VERSION='v4'

##
#  usage : check_root $keepenv
##
orig_argv=("$0" "$@")
check_root() {
	local keepenv=$1

	(( EUID == 0 )) && return
	if type -P sudo >/dev/null; then
		exec sudo --preserve-env=$keepenv -- "${orig_argv[@]}"
	else
		exec su root -c "$(printf ' %q' "${orig_argv[@]}")"
	fi
}

##
#  usage : is_btrfs( $path )
# return : whether $path is on a btrfs
##
is_btrfs() {
	[[ -e "$1" && "$(stat -f -c %T "$1")" == btrfs ]]
}

##
#  usage : is_subvolume( $path )
# return : whether $path is a the root of a btrfs subvolume (including
#          the top-level subvolume).
##
is_subvolume() {
	[[ -e "$1" && "$(stat -f -c %T "$1")" == btrfs && "$(stat -c %i "$1")" == 256 ]]
}

##
#  usage : is_same_fs( $path_a, $path_b )
# return : whether $path_a and $path_b are on the same filesystem
##
is_same_fs() {
	[[ "$(stat -c %d "$1")" == "$(stat -c %d "$1")" ]]
}

##
#  usage : subvolume_delete_recursive( $path )
#
#    Find all btrfs subvolumes under and including $path and delete them.
##
subvolume_delete_recursive() {
	local subvol

	is_subvolume "$1" || return 0

	while IFS= read -d $'\0' -r subvol; do
		if ! subvolume_delete_recursive "$subvol"; then
			return 1
		fi
	done < <(find "$1" -mindepth 1 -xdev -depth -inum 256 -print0)
	if ! btrfs subvolume delete "$1" &>/dev/null; then
		error "Unable to delete subvolume %s" "$subvol"
		return 1
	fi

	return 0
}
