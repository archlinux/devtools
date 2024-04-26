#!/hint/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

[[ -z ${DEVTOOLS_INCLUDE_UTIL_TERM_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_UTIL_TERM_SH=1

set -eo pipefail


readonly PKGCTL_TERM_SPINNER_DOTS=Dots
export PKGCTL_TERM_SPINNER_DOTS
readonly PKGCTL_TERM_SPINNER_DOTS12=Dots12
export PKGCTL_TERM_SPINNER_DOTS12
readonly PKGCTL_TERM_SPINNER_LINE=Line
export PKGCTL_TERM_SPINNER_LINE
readonly PKGCTL_TERM_SPINNER_SIMPLE_DOTS_SCROLLING=SimpleDotsScrolling
export PKGCTL_TERM_SPINNER_SIMPLE_DOTS_SCROLLING
readonly PKGCTL_TERM_SPINNER_TRIANGLE=Triangle
export PKGCTL_TERM_SPINNER_TRIANGLE
readonly PKGCTL_TERM_SPINNER_RANDOM=Random
export PKGCTL_TERM_SPINNER_RANDOM

readonly PKGCTL_TERM_SPINNER_TYPES=(
	"${PKGCTL_TERM_SPINNER_DOTS}"
	"${PKGCTL_TERM_SPINNER_DOTS12}"
	"${PKGCTL_TERM_SPINNER_LINE}"
	"${PKGCTL_TERM_SPINNER_SIMPLE_DOTS_SCROLLING}"
	"${PKGCTL_TERM_SPINNER_TRIANGLE}"
)
export PKGCTL_TERM_SPINNER_TYPES


term_cursor_hide() {
	tput civis >&2
}

term_cursor_show() {
	tput cnorm >&2
}

term_cursor_up() {
	tput cuu1
}

term_carriage_return() {
	tput cr
}

term_erase_line() {
	tput el
}

term_erase_lines() {
	local lines=$1

	local cursor_up erase_line
	cursor_up=$(term_cursor_up)
	erase_line="$(term_carriage_return)$(term_erase_line)"

	local prefix=''
	for _ in $(seq 1 "${lines}"); do
		printf '%s' "${prefix}${erase_line}"
		prefix="${cursor_up}"
	done
}

_pkgctl_spinner_type=${PKGCTL_TERM_SPINNER_RANDOM}
term_spinner_set_type() {
	_pkgctl_spinner_type=$1
}

# takes a status directory that can be used to dynamically update the spinner
# by writing to the `status` file inside that directory atomically.
# replace the placeholder %spinner% with the currently configured spinner type
term_spinner_start() {
	local status_dir=$1
	local parent_pid=$$
	(
		local spinner_type=${_pkgctl_spinner_type}
		local spinner_offset=0
		local frame_buffer=''
		local spinner status_message line

		local status_file="${status_dir}/status"
		local next_file="${status_dir}/next"
		local drawn_file="${status_dir}/drawn"

		# assign random spinner type
		if [[ ${spinner_type} == "${PKGCTL_TERM_SPINNER_RANDOM}" ]]; then
			spinner_type=${PKGCTL_TERM_SPINNER_TYPES[$((RANDOM % ${#PKGCTL_TERM_SPINNER_TYPES[@]}))]}
		fi

		# select spinner based on the named type
		case "${spinner_type}" in
			"${PKGCTL_TERM_SPINNER_DOTS}")
				spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
				update_interval=0.08
				;;
			"${PKGCTL_TERM_SPINNER_DOTS12}")
				spinner=("⢀⠀" "⡀⠀" "⠄⠀" "⢂⠀" "⡂⠀" "⠅⠀" "⢃⠀" "⡃⠀" "⠍⠀" "⢋⠀" "⡋⠀" "⠍⠁" "⢋⠁" "⡋⠁" "⠍⠉" "⠋⠉" "⠋⠉" "⠉⠙" "⠉⠙" "⠉⠩" "⠈⢙" "⠈⡙" "⢈⠩" "⡀⢙" "⠄⡙" "⢂⠩" "⡂⢘" "⠅⡘" "⢃⠨" "⡃⢐" "⠍⡐" "⢋⠠" "⡋⢀" "⠍⡁" "⢋⠁" "⡋⠁" "⠍⠉" "⠋⠉" "⠋⠉" "⠉⠙" "⠉⠙" "⠉⠩" "⠈⢙" "⠈⡙" "⠈⠩" "⠀⢙" "⠀⡙" "⠀⠩" "⠀⢘" "⠀⡘" "⠀⠨" "⠀⢐" "⠀⡐" "⠀⠠" "⠀⢀" "⠀⡀")
				update_interval=0.08
				;;
			"${PKGCTL_TERM_SPINNER_LINE}")
				spinner=("⎯" "\\" "|" "/")
				update_interval=0.13
				;;
			"${PKGCTL_TERM_SPINNER_SIMPLE_DOTS_SCROLLING}")
				spinner=(".  " ".. " "..." " .." "  ." "   ")
				update_interval=0.2
				;;
			"${PKGCTL_TERM_SPINNER_TRIANGLE}")
				spinner=("◢" "◣" "◤" "◥")
				update_interval=0.05
				;;
		esac

		# hide the cursor while spinning
		term_cursor_hide

		# run the spinner as long as the parent process didn't terminate
		while ps -p "${parent_pid}" &>/dev/null; do
			# cache the new status template if it exists
			if mv "${status_file}" "${next_file}" &>/dev/null; then
				status_message="$(cat "$next_file")"
			elif [[ -z "${status_message}" ]]; then
				# wait until we either have a new or cached status
				sleep 0.05
			fi

			# fill the frame buffer with the current status
			local prefix=''
			while IFS= read -r line; do
				# replace spinner placeholder
				line=${line//%spinner%/${spinner[spinner_offset%${#spinner[@]}]}}

				# append the current line to the frame buffer
				frame_buffer+="${prefix}${line}"
				prefix=$'\n'
			done <<< "${status_message}"

			# print current frame buffer
			echo -n "${frame_buffer}" >&2
			mv "${next_file}" "${drawn_file}" &>/dev/null ||:

			# setup next frame buffer to clear current content
			frame_buffer=$(term_erase_lines "$(awk 'END {print NR}' <<< "${status_message}")")

			# advance the spinner animation offset
			(( ++spinner_offset ))

			# sleep for the spinner update interval
			sleep "${update_interval}"
		done
	)&
	_pkgctl_spinner_pid=$!
	disown
}

term_spinner_stop() {
	local status_dir=$1
	local frame_buffer status_file

	# kill the spinner process
	if ! kill "${_pkgctl_spinner_pid}" > /dev/null 2>&1; then
		return 1
	fi
	unset _pkgctl_spinner_pid

	# acquire last drawn status
	status_file="${status_dir}/drawn"
	if [[ ! -f ${status_file} ]]; then
		return 0
	fi

	# clear terminal based on last status line
	frame_buffer=$(term_erase_lines "$(awk 'END {print NR}' < "${status_file}")")
	echo -n "${frame_buffer}" >&2

	# show the cursor after stopping the spinner
	term_cursor_show
}

prompt() {
	local message=$1
	local answer

	read -r -p "${message} (y/N) " answer

	case "${answer}" in
		y|Y|yes|Yes|YES)
			true
			;;
		*)
			false
			;;
	esac
}
