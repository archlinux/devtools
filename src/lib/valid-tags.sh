#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
:

# shellcheck disable=2034
DEVTOOLS_VALID_BINARY_ARCHES=(
	x86_64
)

# shellcheck disable=2034
DEVTOOLS_VALID_ARCHES=(
	"${DEVTOOLS_VALID_BINARY_ARCHES[@]}"
	any
)

# shellcheck disable=2034
DEVTOOLS_VALID_TAGS=(
	core-x86_64 core-any
	core-staging-x86_64 core-staging-any
	core-testing-x86_64 core-testing-any
	extra-x86_64 extra-any
	extra-staging-x86_64 extra-staging-any
	extra-testing-x86_64 extra-testing-any
	multilib-x86_64
	multilib-testing-x86_64
	multilib-staging-x86_64
	kde-unstable-x86_64 kde-unstable-any
	gnome-unstable-x86_64 gnome-unstable-any
)
