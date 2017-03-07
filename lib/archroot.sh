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
