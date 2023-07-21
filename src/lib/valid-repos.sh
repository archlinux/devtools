#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
:

# shellcheck disable=2034
DEVTOOLS_VALID_REPOS=(
	core core-staging core-testing
	extra extra-staging extra-testing
	multilib multilib-staging multilib-testing
	gnome-unstable
	kde-unstable
)

# shellcheck disable=2034
DEVTOOLS_VALID_BUILDREPOS=(
	core-staging core-testing
	extra extra-staging extra-testing
	multilib multilib-staging multilib-testing
	gnome-unstable
	kde-unstable
)
