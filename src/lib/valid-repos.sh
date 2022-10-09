#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
:

# shellcheck disable=2034
_repos=(
	staging
	testing
	core
	extra
	community-staging
	community-testing
	community
	multilib-staging
	multilib-testing
	multilib
	gnome-unstable
	kde-unstable
)

# shellcheck disable=2034
_build_repos=(
	staging
	testing
	extra
	multilib-staging
	multilib-testing
	multilib
	gnome-unstable
	kde-unstable
)
