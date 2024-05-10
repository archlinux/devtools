#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_VERSION_SETUP_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_SETUP_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/version/check.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/check.sh

source /usr/share/makepkg/util/message.sh
source /usr/share/makepkg/util/source.sh

set -eo pipefail


pkgctl_version_setup_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Automate the creation of a basic nvchecker configuration file by
		analyzing the source array specified in the PKGBUILD file of a package.

		If no PKGBASE is specified, the command defaults to using the current
		working directory.

		OPTIONS
		    -f, --force            Overwrite existing nvchecker configuration
		    --prefer-platform-api  Prefer platform specific GitHub/GitLab API for complex cases
		    --url URL              Derive check target from URL instead of source array
		    --no-check             Do not run version check after setup
		    -h, --help             Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_version_setup() {
	local pkgbases=()
	local override_url=
	local run_check=1
	local force=0
	local prefer_platform_api=0

	local path ret
	local checks=()

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_setup_usage
				exit 0
				;;
			-f|--force)
				force=1
				shift
				;;
			--prefer-platform-api)
				prefer_platform_api=1
				shift
				;;
			--url)
				(( $# <= 1 )) && die "missing argument for %s" "$1"
				override_url=$2
				shift 2
				;;
			--no-check)
				run_check=0
				shift
				;;
			--)
				shift
				break
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				pkgbases=("$@")
				break
				;;
		esac
	done

	# Check if used without pkgbases in a packaging directory
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			pkgbases=(".")
		else
			pkgctl_version_setup_usage
			exit 1
		fi
	fi

	ret=0
	for path in "${pkgbases[@]}"; do
		# skip paths that are not directories
		if [[ ! -d "${path}" ]]; then
			continue
		fi

		pushd "${path}" >/dev/null
		if nvchecker_setup "${path}" "${force}" "${prefer_platform_api}" "${override_url}"; then
			checks+=("${path}")
		else
			ret=1
		fi
		popd >/dev/null
	done

	# run checks on the setup targets
	if (( run_check )) && (( ${#checks[@]} >= 1 )); then
		echo
		pkgctl_version_check --verbose "${checks[@]}" || true
	fi

	return $ret
}

nvchecker_setup() {
	local path=$1
	local force=$2
	local prefer_platform_api=$3
	local override_url=$4
	local pkgbase pkgname source source_url proto domain url_parts section body

	if [[ ! -f PKGBUILD ]]; then
		msg_error "${BOLD}${path}:${ALL_OFF} no PKGBUILD found"
		return 1
	fi

	unset body pkgbase pkgname source url
	# shellcheck source=contrib/makepkg/PKGBUILD.proto
	if ! . ./PKGBUILD; then
		msg_error "${BOLD}${path}:${ALL_OFF} failed to source PKGBUILD"
		return 1
	fi
	pkgbase=${pkgbase:-$pkgname}

	# try to guess from url as last try
	if [[ -n ${url} ]]; then
		source+=("${url}")
	fi

	# handle overwrite of existing config
	if [[ -f .nvchecker.toml ]] && (( ! force )); then
		msg_warn "${BOLD}${pkgbase}:${ALL_OFF} nvchecker already configured"
		return 1
	fi

	# override the source array with a passed URL
	if [[ -n ${override_url} ]]; then
		source=("${override_url}")
	fi

	# skip empty source array
	if (( ${#source[@]} == 0 )); then
		msg_error "${BOLD}${pkgbase}:${ALL_OFF} PKGBUILD has no source array"
		return 1
	fi

	for source_url in "${source[@]}"; do
		# Strips out filename::http for example
		source_url=$(get_url "${source_url}")
		# discard query fragments
		source_url=${source_url%\?*}
		source_url=${source_url%#*}

		# skip patches
		if [[ ${source_url} == *.patch ]]; then
			continue
		fi
		# skip signatures
		if [[ ${source_url} == *.asc ]] || [[ ${source_url} == *.sig ]]; then
			continue
		fi
		# skip local files
		if [[ ${source_url} != *://* ]]; then
			continue
		fi

		# split URL segments while avoiding empty element after protocol and newline at the end
		mapfile -td / url_parts <<< "${source_url/:\/\//\/}/"
		unset "url_parts[-1]"

		# extract protocol and domain to select the configuration type
		proto=${url_parts[0]}
		domain=${url_parts[1]}

		case "${domain}" in
			gitlab.*)
				if (( prefer_platform_api )); then
					body=$(nvchecker_setup_gitlab "${url_parts[@]}")
				else
					body=$(nvchecker_setup_git "${url_parts[@]}")
				fi
				break
				;;
			github.com)
				if (( prefer_platform_api )); then
					body=$(nvchecker_setup_github "${url_parts[@]}")
				else
					body=$(nvchecker_setup_git "${url_parts[@]}")
				fi
				break
				;;
			codeberg.org)
				body=$(nvchecker_setup_git "${url_parts[@]}")
				break
				;;
			pypi.org|pypi.io|files.pythonhosted.org)
				body=$(nvchecker_setup_pypi "${url_parts[@]}")
				break
				;;
			hackage.haskell.org)
				body=$(nvchecker_setup_hackage "${url_parts[@]}")
				break
				;;
			registry.npmjs.org|npmjs.com|www.npmjs.com)
				body=$(nvchecker_setup_npm "${url_parts[@]}")
				break
				;;
			rubygems.org)
				body=$(nvchecker_setup_rubygems "${url_parts[@]}")
				break
				;;
			*.cpan.org|*.mcpan.org|*.metacpan.org)
				body=$(nvchecker_setup_cpan "${url_parts[@]}")
				break
				;;
			crates.io|*.crates.io)
				body=$(nvchecker_setup_crates_io "${url_parts[@]}")
				break
				;;
			*)
				if [[ ${proto} == git ]] || [[ ${proto} == git+https ]]; then
					body=$(nvchecker_setup_git "${url_parts[@]}")
				fi
				;;
		esac
	done

	if [[ -z "${body}" ]]; then
		msg_error "${BOLD}${pkgbase}:${ALL_OFF} unable to automatically setup nvchecker"
		return 1
	fi

	# escape the section if it contains toml subsection chars
	section="${pkgbase}"
	if [[ ${section} == *.* ]] || [[ ${section} == *+* ]]; then
		section="\"${section}\""
	fi

	msg_success "${BOLD}${pkgbase}:${ALL_OFF} successfully configured nvchecker"
	cat > .nvchecker.toml << EOF
[${section}]
${body}
EOF
}

get_git_url_from_parts() {
	local url_parts=("$@")
	local proto=${url_parts[0]#*+}
	local domain=${url_parts[1]}
	local url
	url="${proto}://$(join_by / "${url_parts[@]:1}")"

	case "${domain}" in
		gitlab.*)
			url=${url%/-/*/*}
			[[ ${url} != *.git ]] && url+=.git
			;;
		github.com|codeberg.org)
			url="${proto}://$(join_by / "${url_parts[@]:1:3}")"
			[[ ${url} != *.git ]] && url+=.git
			;;
	esac

	printf '%s' "${url}"
}

# PyPI
#
# As Arch python packages don't necessarily match the pypi name, when the
# provided source url comes from pypi.io or pypi.org try to extract the package
# name from the (predictable) tarball download url for example:
#
# https://pypi.io/packages/source/p/pyflakes/pyflakes-3.1.0.tar.gz
# https://pypi.io/packages/source/p/pyflakes
# https://pypi.org/packages/source/b/bleach
# https://files.pythonhosted.org/packages/source/p/pyflakes
# https://pypi.org/project/SQLAlchemy/
nvchecker_setup_pypi() {
	local url_parts=("$@")
	local pypi

	if [[ ${url_parts[2]} == packages ]]; then
		pypi=${url_parts[5]}
	elif [[ ${url_parts[2]} == project ]]; then
		pypi=${url_parts[3]}
	else
		return 1
	fi

	cat << EOF
source = "pypi"
pypi = "${pypi}"
EOF
}

# Git
#
# Set up a generic Git source, while removing the proto specific part from makepkg
#
# git+https://github.com/prometheus/prometheus.git
# https://git.foobar.com/some/path/group/project.git
# https://gitlab.com/sub/group/project/-/archive/8.0.0/packages-8.0.0.tar.gz
nvchecker_setup_git() {
	local url_parts=("$@")
	local url
	url=$(get_git_url_from_parts "${url_parts[@]}")

	cat << EOF
source = "git"
git = "${url}"
EOF

	# best effort check if the tags are prefixed with v
	if git_tags_have_version_prefix "${url}"; then
		echo 'prefix = "v"'
	fi
}

git_tags_have_version_prefix() {
	local url=$1
	# best effort check if the tags are prefixed with v
	if ! grep --max-count=1 --quiet --extended-regex 'refs/tags/v[0-9]+[\.0-9]*$' \
		<(GIT_TERMINAL_PROMPT=0 git ls-remote --quiet --tags "${url}" 2>/dev/null); then
		return 1
	fi
	return 0
}

# Github
#
# We want to know the $org/$project name from the url
#
# https://github.com/prometheus/prometheus/archive/v2.49.1.tar.gz
nvchecker_setup_github() {
	local url_parts=("$@")
	local url project
	if ! url=$(get_git_url_from_parts "${url_parts[@]}"); then
		return 1
	fi
	project=${url#*://*/}
	project=${project%.git}

	cat << EOF
source = "github"
github = "${project}"
use_max_tag = true
EOF

	# best effort check if the tags are prefixed with v
	if git_tags_have_version_prefix "${url}"; then
		echo 'prefix = "v"'
	fi
}

# GitLab
#
# We want to know the $org/$project name from the url
#
# git+https://gitlab.com/inkscape/inkscape.git#tag=091e20ef0f204eb40ecde54436e1ef934a03d894
nvchecker_setup_gitlab() {
	local url_parts=("$@")
	local url project host
	if ! url=$(get_git_url_from_parts "${url_parts[@]}"); then
		return 1
	fi
	project=${url#*://*/}
	project=${project%.git}
	cat << EOF
source = "gitlab"
gitlab = "${project}"
EOF

	host=${url#*://}
	host=${host%%/*}
	if [[ ${host} != gitlab.com ]]; then
		echo "host = \"${host}\""
	fi

	echo "use_max_tag = true"

	# best effort check if the tags are prefixed with v
	if git_tags_have_version_prefix "${url}"; then
		echo 'prefix = "v"'
	fi
}

# Hackage
#
# We want to know the project name
#
# https://hackage.haskell.org/package/xmonad
# https://hackage.haskell.org/package/xmonad-0.18.0/xmonad-0.18.0.tar.gz
# https://hackage.haskell.org/packages/archive/digits/0.3.1/digits-0.3.1.tar.gz
nvchecker_setup_hackage() {
	local url_parts=("$@")
	local hackage

	if [[ ${url_parts[2]} == packages ]]; then
		hackage=${url_parts[4]}
	elif [[ ${url_parts[2]} == package ]] && (( ${#url_parts[@]} == 4 )); then
		hackage=${url_parts[3]}
	elif [[ ${url_parts[2]} == package ]] && (( ${#url_parts[@]} >= 5 )); then
		hackage=${url_parts[3]%-*}
	else
		return 1
	fi

	cat << EOF
source = "hackage"
hackage = "${hackage}"
EOF
}

# NPM
#
# We want to know the project name
#
# https://registry.npmjs.org/eslint_d/-/eslint_d-12.1.0.tgz
# https://www.npmjs.com/package/node-gyp
nvchecker_setup_npm() {
	local url_parts=("$@")
	local npm

	if [[ ${url_parts[1]} == registry.npmjs.org ]]; then
		npm=${url_parts[2]}
	elif [[ ${url_parts[2]} == package ]] && (( ${#url_parts[@]} == 4 )); then
		npm=${url_parts[3]}
	else
		return 1
	fi

	cat << EOF
source = "npm"
npm = "${npm}"
EOF
}

# RubyGems
#
# We want to know the project name
#
# https://rubygems.org/downloads/polyglot-0.3.5.gem
# https://rubygems.org/gems/diff-lcs
nvchecker_setup_rubygems() {
	local url_parts=("$@")
	local gem

	if [[ ${url_parts[2]} == downloads ]]; then
		gem=${url_parts[-1]%-*}
	elif [[ ${url_parts[2]} == gems ]]; then
		gem=${url_parts[3]}
	else
		return 1
	fi

	cat << EOF
source = "gems"
gems = "${gem}"
EOF
}

# CPAN
#
# We want to know the project name
#
# source = https://search.cpan.org/CPAN/authors/id/C/CO/COSIMO/Locale-PO-1.2.3.tar.gz
nvchecker_setup_cpan() {
	local url_parts=("$@")
	local cpan=${url_parts[-1]}
	cpan=${cpan%-*}

	cat << EOF
source = "cpan"
cpan = "${cpan}"
EOF
}

# crates.io
#
# We want to know the crate name
#
# https://crates.io/api/v1/crates/${pkgname}/${pkgver}/download
# https://static.crates.io/crates/${pkgname}/$pkgname-$pkgver.crate
# https://crates.io/crates/git-smash
nvchecker_setup_crates_io() {
	local url_parts=("$@")
	local crate

	if [[ ${url_parts[2]} == crates ]]; then
		crate=${url_parts[3]}
	elif [[ ${url_parts[4]} == crates ]]; then
		crate=${url_parts[5]}
	else
		return 1
	fi


	for i in "${!url_parts[@]}"; do
		if [[ ${url_parts[i]} == crates ]]; then
			crate=${url_parts[(( i + 1 ))]}
		fi
	done

	cat << EOF
source = "cratesio"
cratesio = "${crate}"
EOF
}
