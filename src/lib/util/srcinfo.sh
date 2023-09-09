#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_SRCINFO_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_SRCINFO_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

source /usr/share/makepkg/util/util.sh
source /usr/share/makepkg/srcinfo.sh

set -eo pipefail


print_srcinfo() {
	local pkgpath=${1:-.}
	local outdir pkg pid
	local pids=()

	# source the PKGBUILD
	# shellcheck source=contrib/makepkg/PKGBUILD.proto
	. "${pkgpath}"/PKGBUILD

	# run without parallelization for single packages
	if (( ${#pkgname[@]} == 1 )); then
		write_srcinfo_content
		return 0
	fi

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	outdir=$(mktemp --directory --tmpdir="${WORKDIR}" pkgctl-srcinfo.XXXXXXXXXX)

	# fork workload for each split pkgname
	for pkg in "${pkgname[@]}"; do
		(
			# deactivate errexit to avoid makepkg abort on grep_function
			set +e
			srcinfo_write_package "$pkg" > "${outdir}/${pkg}"
		)&
		pids+=($!)
	done

	# join workload
	for pid in "${pids[@]}"; do
		if ! wait "${pid}"; then
			return 1
		fi
	done

	# collect output
	srcinfo_write_global
	for pkg in "${pkgname[@]}"; do
		srcinfo_separate_section
		cat "${outdir}/${pkg}"
	done
}

write_srcinfo_file() {
	local pkgpath=${1:-.}
	stat_busy 'Generating .SRCINFO'
	if ! print_srcinfo "${pkgpath}" > "${pkgpath}"/.SRCINFO; then
		error 'Failed to write .SRCINFO file'
		return 1
	fi
	stat_done
}
