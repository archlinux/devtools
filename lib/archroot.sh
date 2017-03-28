#!/hint/bash
# License: Unspecified

CHROOT_VERSION='v4'

##
#  usage : check_root
##
orig_argv=("$0" "$@")
check_root() {
	(( EUID == 0 )) && return
	if type -P sudo >/dev/null; then
		exec sudo -- "${orig_argv[@]}"
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
#  usage : subvolume_delete_recursive( $path )
#
#    Find all btrfs subvolumes under and including $path and delete them.
##
subvolume_delete_recursive() {
	local subvol

	is_btrfs "$1" || return 0

	while IFS= read -d $'\0' -r subvol; do
		if ! btrfs subvolume delete "$subvol" &>/dev/null; then
			error "Unable to delete subvolume %s" "$subvol"
			return 1
		fi
	done < <(find "$1" -xdev -depth -inum 256 -print0)

	return 0
}
