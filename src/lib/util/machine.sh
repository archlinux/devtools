#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_MACHINE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_MACHINE_SH=1


# Usage: machine_name(name)
machine_name() {
	local name=$1

	local tool="${0##*/}"
	local machine="${tool}-${name}"
	local max_hostname=64  # see gethostname(2)
	local max_pid_digits=7  # ceil(log(2^22, 10))

	# Normalize the package name so it doubles as a valid hostname
	# https://github.com/systemd/systemd/blob/v256/src/basic/hostname-util.c#L83-L136
	machine="$(
		tr --squeeze-repeats --complement 'a-z0-9.' - <<< "${machine}" | \
			tr --squeeze-repeats '.' | \
			head --bytes=$(( max_hostname - max_pid_digits - 1 ))
	)"

	# Drop all trailing '-' or '.' characters
	machine=$(printf "%s" "${machine}" | sed --regexp-extended 's/-+$//;s/\.+$//')

	printf "%s.%s" "${machine}" "$$"
}
