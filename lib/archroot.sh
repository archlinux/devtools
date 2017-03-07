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
