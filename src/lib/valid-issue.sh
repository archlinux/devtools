#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_SEVERITY=(
	lowest
	low
	medium
	high
	critical
)

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_PRIORITY=(
	low
	normal
	high
	urgent
)

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_STATUS=(
	confirmed
	in-progress
	in-review
	on-hold
	unconfirmed
	waiting-input
	waiting-upstream
)

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_SCOPE=(
	bug
	feature
	security
	question
	regression
	enhancement
	documentation
	reproducibility
	out-of-date
)

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_SEARCH_LOCATION=(
	title
	description
	all
)

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_RESOLUTION=(
	cant-reproduce
	completed
	duplicate
	invalid
	not-a-bug
	upstream
	wont-fix
)

# shellcheck disable=2034
DEVTOOLS_VALID_ISSUE_CONFIDENTIALITY=(
	confidential
	public
)
