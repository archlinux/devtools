#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_API_ARCHWEB_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_API_ARCHWEB_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh

set -e
set -o pipefail


archweb_query_all_packages() {
	[[ -z ${WORKDIR:-} ]] && setup_workdir

	stat_busy "Query all released packages"
	mapfile -t pkgbases < <(
		curl --location --show-error --no-progress-meter --fail --retry 3 --retry-delay 3 \
			"${PKGBASE_MAINTAINER_URL}" 2> "${WORKDIR}/error" \
			| jq --raw-output --exit-status 'keys[]' 2> "${WORKDIR}/error"
	)
	if ! wait $!; then
		stat_failed
		print_workdir_error
		return 1
	fi
	stat_done

	printf "%s\n" "${pkgbases[@]}"
	return 0
}


archweb_query_maintainer_packages() {
	local maintainer=$1

	[[ -z ${WORKDIR:-} ]] && setup_workdir

	stat_busy "Query maintainer packages"
	mapfile -t pkgbases < <(
		curl --location --show-error --no-progress-meter --fail --retry 3 --retry-delay 3 \
			"${PKGBASE_MAINTAINER_URL}" 2> "${WORKDIR}/error" \
			| jq --raw-output --exit-status '. as $parent | keys[] | select(. as $key | $parent[$key] | index("'"${maintainer}"'"))' 2> "${WORKDIR}/error"
	)
	if ! wait $!; then
		stat_failed
		print_workdir_error
		return 1
	fi
	stat_done

	printf "%s\n" "${pkgbases[@]}"
	return 0
}
