#!/hint/bash

# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_BUILD_OFFLOAD_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_BUILD_OFFLOAD_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/util/makepkg.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/makepkg.sh

source /usr/share/makepkg/util/config.sh
source /usr/share/makepkg/util/message.sh

set -eo pipefail


PKGCTL_OFFLOAD_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/pkgctl/offload"

pkgctl_build_offload_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [COMMAND] [OPTIONS]...

		Server commands to build packages remotely by offloading the job.

		For internal use only!
_EOF_
}

pkgctl_build_offload() {
	if (( $# < 1 )); then
		pkgctl_build_offload_usage
		exit 1
	fi

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_build_offload_usage
				exit 0
				;;
			create-builddir)
				shift
				pkgctl_build_offload_server_create_builddir "$@"
				exit 0
				;;
			clean-builddir)
				shift
				pkgctl_build_offload_server_clean_builddir "$@"
				exit 0
				;;
			build)
				shift
				pkgctl_build_offload_server_build "$@"
				exit 0
				;;
			collect-files)
				shift
				pkgctl_build_offload_server_collect_files "$@"
				exit 0
				;;
			collect-logs)
				shift
				pkgctl_build_offload_server_collect_logs "$@"
				exit 0
				;;
			*)
				die "invalid argument: %s" "$1"
				;;
		esac
	done
}

pkgctl_build_offload_client() {
	local pkgbase=$1
	local pkgrepo=$2
	local pkgarch=$3
	shift 3
	local server=build.archlinux.org
	# shellcheck disable=SC2031
	local working_dir=$PWD
	local _srcpkg srcpkg files

	[[ -z ${WORKDIR:-} ]] && setup_workdir
	TEMPDIR=$(mktemp --tmpdir="${WORKDIR}" --directory "offload.${pkgbase}.${pkgrepo}-${pkgarch}XXXXXXXXXX")

	# Load makepkg.conf variables to be available
	# shellcheck disable=SC2119
	load_makepkg_config

	# Use a source-only tarball as an intermediate to transfer files. This
	# guarantees the checksums are okay, and guarantees that all needed files are
	# transferred, including local sources, install scripts, and changelogs.
	export SRCPKGDEST="${TEMPDIR}"
	if ! makepkg_source_package; then
		die "unable to make source package"
		return 1
	fi

	# Temporary cosmetic workaround makepkg if SRCDEST is set somewhere else
	# but an empty src dir is created in PWD. Remove once fixed in makepkg.
	rmdir --ignore-fail-on-non-empty src 2>/dev/null || true

	local builddir
	builddir=$(
		ssh "${SSH_OPTS[@]}" -- "$server" pkgctl offload create-builddir "${pkgbase@Q}" "${pkgrepo@Q}" "${pkgarch@Q}"
	)

	# Transfer the srcpkg to the server
	msg "Transferring source package to the server..."
	_srcpkg=("$SRCPKGDEST"/*"$SRCEXT")
	srcpkg="${_srcpkg[0]}"
	if ! rsync "${RSYNC_OPTS[@]}" -- "$srcpkg" "$server":"${builddir}"; then
		die "failed to rsync sources to offload server"
		return 1
	fi

	# Execute build
	if ssh "${SSH_OPTS[@]}" -t -- "$server" pkgctl offload build "${builddir@Q}" "${srcpkg@Q}" "${pkgrepo@Q}" "${pkgarch@Q}" "${@@Q}"; then
		# Get an array of files that should be downloaded from the server
		mapfile -t files < <(
			ssh "${SSH_OPTS[@]}" -- "$server" pkgctl offload collect-files "${builddir@Q}" "${pkgrepo@Q}" "${pkgarch@Q}"
		)
	else
		# Build failed, only the logs should be downloaded from the server
		mapfile -t files < <(
			ssh "${SSH_OPTS[@]}" -- "$server" pkgctl offload collect-logs "${builddir@Q}"
		)
	fi

	# Check if we collected any files to download
	if (( ${#files[@]} == 0 )); then
		die "failed to collect files to download"
		return 1
	fi

	msg 'Downloading files...'
	rsync "${RSYNC_OPTS[@]}" -- "${files[@]/#/$server:}" "${TEMPDIR}/"

	# Clean remote build dir
	ssh "${SSH_OPTS[@]}" -- "$server" pkgctl offload clean-builddir "${builddir@Q}"

	# Move all log files to LOGDEST
	if is_globfile "${TEMPDIR}"/*.log; then
		mv "${TEMPDIR}"/*.log "${LOGDEST:-${working_dir}}/"
	fi

	# Assume build failed if we didn't download any package files
	if ! is_globfile "${TEMPDIR}"/*.pkg.tar*; then
		error "Build failed, check logs in ${LOGDEST:-${working_dir}}"
		return 1
	fi

	# Building a package may change the PKGBUILD during update_pkgver
	mv "${TEMPDIR}/PKGBUILD" "${working_dir}/"
	mv "${TEMPDIR}"/*.pkg.tar* "${PKGDEST:-${working_dir}}/"
	return 0
}

pkgctl_build_offload_server_build() {
	local builddir=$1
	local srcpkg=$2
	local pkgrepo=$3
	local pkgarch=$4
	shift 4
	local buildtool

	if [[ -n $pkgarch ]]; then
		buildtool="${pkgrepo}-${pkgarch}-build"
	else
		buildtool="${pkgrepo}-build"
	fi

	cd "${builddir}"
	bsdtar --strip-components 1 -xvf "$(basename "$srcpkg")"
	LOGDEST="" "${buildtool}" "$@"
}

pkgctl_build_offload_server_create_builddir() {
	local pkgbase=$1
	local pkgrepo=$2
	local pkgarch=$3
	mkdir --parents "${PKGCTL_OFFLOAD_CACHE_HOME}"
	mktemp --directory --tmpdir="${PKGCTL_OFFLOAD_CACHE_HOME}" "${pkgbase}.${pkgrepo}-${pkgarch}XXXXXXXXXX"
}

pkgctl_build_offload_server_clean_builddir() {
	local builddir=$1
	rm --recursive --force -- "${builddir}"
}

pkgctl_build_offload_server_collect_files() {
	local builddir=$1
	local pkgrepo=$2
	local pkgarch=$3

	local makepkg_config
	local makepkg_user_config

	# fallback config for multilib
	if [[ ${pkgrepo} == multilib* ]] && [[ -z ${pkgarch} ]]; then
		pkgarch=x86_64
	fi

	cd "${builddir}"
	makepkg_user_config="${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf"
	makepkg_config="${_DEVTOOLS_LIBRARY_DIR}/makepkg.conf.d/${pkgarch}.conf"
	if [[ -f ${_DEVTOOLS_LIBRARY_DIR}/makepkg.conf.d/${pkgrepo}-${pkgarch}.conf ]]; then
		makepkg_config="${_DEVTOOLS_LIBRARY_DIR}/makepkg.conf.d/${pkgrepo}-${pkgarch}.conf"
	fi
	while read -r file; do
		if [[ -f "${file}" ]]; then
			printf "%s\n" "${file}"
		fi
	done < <(makepkg --config <(cat "${makepkg_user_config}" "${makepkg_config}" 2>/dev/null) --packagelist)

	printf "%s\n" "${builddir}/PKGBUILD"

	pkgctl_build_offload_server_collect_logs "${builddir}"
}

pkgctl_build_offload_server_collect_logs() {
	local builddir=$1
	find "${builddir}" -name "*.log"
}
