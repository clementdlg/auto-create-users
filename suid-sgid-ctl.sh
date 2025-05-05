#!/usr/bin/env bash

set -euo pipefail

error() {
	msg="$1"
	echo "Error : $msg" 1>&2
}

init() {
	if [[ $EUID -ne 0 ]]; then
		error "Run this script as root"
		return 1
	fi
}

show_usage() {
	echo "Usage :"
	echo "-u : show SUID files"
	echo "-g : show SGID files"
	echo "-gu / -ug / no args : show both"
	exit 0
}

show_info() {
	echo "SUID : $_SHOW_SUID"
	echo "SGID : $_SHOW_SGID"
}

check_args() {

	if (( $# == 0 )); then
		_SHOW_SUID="y"
		_SHOW_SGID="y"

	elif (( $# == 1 )); then
		if [[ "$1" == "-u" ]]; then
			_SHOW_SUID="y"

		elif [[ "$1" == "-g" ]]; then
			_SHOW_SGID="y"

		elif [[ "$1" == "-gu" || "$1" == "-ug" ]]; then
			_SHOW_SUID="y"
			_SHOW_SGID="y"
		else
			show_usage
		fi

	elif (( $# == 2 )); then
		if [[ "$1" == "-u" && "$2" == "-g" \
			|| "$1" == "-g" && "$2" == "-u" ]]; then
			_SHOW_SUID="y"
			_SHOW_SGID="y"
		else 
			show_usage
		fi
	else
		show_usage
	fi
}

set_mode() {
	if [[ "$_SHOW_SUID" == "y" && "$_SHOW_SGID" == "y" ]]; then
		_DISPLAY_MODE="suid_sgid"
		_PERM="-2000 -o -perm -4000"

	elif [[ "$_SHOW_SUID" == "y" ]]; then
		_DISPLAY_MODE="suid_only"
		_PERM="-4000"

	else
		_DISPLAY_MODE="sgid_only"
		_PERM="-2000"

	fi

	echo "Selected mode : $_DISPLAY_MODE"
}

set_workspace() {
	if [[ ! -f "$_WORKSPACE" ]]; then
		mkdir -p "$_WORKSPACE"
	fi

	timestamp="$(date +%H-%M-%S)"

	_FILE_NAME="${_DISPLAY_MODE}_${timestamp}.list"

	echo "" > "$_FILE_NAME"
}

create_list() {
	echo "Creating new list list..."

	modification_time="%TY-%Tm-%Td %TH:%TM:%TS"
	full_path="$_WORKSPACE/$_FILE_NAME"

	set +e

	find / \( -perm $_PERM \) -type f -fprintf "$full_path" "%p ${modification_time}\n" 2>/dev/null
	set -e

	count="$(wc -l "$full_path" | awk '{print $1}')"

	echo "List was created at $full_path"
	echo "Found ($count) elements for $_DISPLAY_MODE"
}

diff_list() {
	prev_list=""
}

main() {
	_SHOW_SUID="n"
	_SHOW_SGID="n"
	_DISPLAY_MODE=""
	_WORKSPACE="/var/tmp/$(basename "$0")"
	_FILE_NAME=""
	_PERM=""

	init
	check_args "$@"
	set_mode
	set_workspace
	create_list
	# diff_list
}

main "$@"
