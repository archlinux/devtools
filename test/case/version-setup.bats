bats_require_minimum_version 1.5.0

export _DEVTOOLS_LIBRARY_DIR="${PWD}/src"

_pkgctl_version_setup() {
	source ${_DEVTOOLS_LIBRARY_DIR}/lib/version/setup.sh
	pkgctl_version_setup "$@"
}

setup_and_check_config() {
	pushd "test/fixture/version/setup/$1"
	shift
	_pkgctl_version_setup --force --no-check "$@"
	diff .nvchecker.toml nvchecker.assert.toml
	popd
}

@test "opt-no-force" {
	pushd test/fixture/version/setup/opt-no-force
	touch .nvchecker.toml
	run ! _pkgctl_version_setup --no-check "$@"
	popd
}

@test "opt-url" {
	pushd test/fixture/version/setup/opt-url
	_pkgctl_version_setup --no-check --force --url \
		"https://crates.io/api/v1/crates/shotgun/1.0/download" "$@"
	diff .nvchecker.toml nvchecker.assert.toml
	popd
}

@test "codeberg-tarball" {
	setup_and_check_config codeberg-tarball
}

@test "files.pythonhosted.org" {
	setup_and_check_config files.pythonhosted.org
}

@test "github-git" {
	setup_and_check_config github-git
}

@test "github-git-as-platform" {
	setup_and_check_config github-git-as-platform --prefer-platform-api
}

@test "github-git-v-prefix" {
	setup_and_check_config github-git-v-prefix
}

@test "github-git-v-prefix-as-platform" {
	setup_and_check_config github-git-v-prefix-as-platform --prefer-platform-api
}

@test "github-tarball" {
	setup_and_check_config github-tarball
}

@test "github-tarball-as-platform" {
	setup_and_check_config github-tarball-as-platform --prefer-platform-api
}

@test "gitlab-archlinux-tarball" {
	setup_and_check_config gitlab-archlinux-tarball
}

@test "gitlab-archlinux-tarball-as-platform" {
	setup_and_check_config gitlab-archlinux-tarball-as-platform --prefer-platform-api
}

@test "gitlab-git-multi-group" {
	setup_and_check_config gitlab-git-multi-group
}

@test "gitlab-git-multi-group-as-platform" {
	setup_and_check_config gitlab-git-multi-group-as-platform --prefer-platform-api
}

@test "gitlab-tarball-multi-group" {
	setup_and_check_config gitlab-tarball-multi-group
}

@test "gitlab-tarball-multi-group-as-platform" {
	setup_and_check_config gitlab-tarball-multi-group-as-platform --prefer-platform-api
}

@test "hackage-tarball" {
	setup_and_check_config hackage-tarball
}

@test "pkgbase-with-dot" {
	setup_and_check_config pkgbase-with-dot
}

@test "pypi.io" {
	setup_and_check_config pypi.io
}

@test "pypi.org" {
	setup_and_check_config pypi.org
}

@test "registry.npmjs.org" {
	setup_and_check_config registry.npmjs.org
}

@test "git-custom" {
	setup_and_check_config git-custom
}

@test "rubygems.org" {
	setup_and_check_config rubygems.org
}

@test "cpan.org" {
	setup_and_check_config cpan.org
}

@test "crates.io" {
	setup_and_check_config crates.io
}

@test "static.crates.io" {
	setup_and_check_config static.crates.io
}
