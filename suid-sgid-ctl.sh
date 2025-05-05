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

	timestamp="$(date +%Y-%m-%d-%H-%M-%S)"

	_FILE_NAME="${_DISPLAY_MODE}_${timestamp}.list"

	# echo "" > "$_WORKSPACE/$_FILE_NAME"
}

set_previous_file() {
	_PREVIOUS_FILE="$(find "$_WORKSPACE" \
		-type f \
		-name "${_DISPLAY_MODE}_*" \
		| sort -n \
		| tail -1)"
}

create_list() {
	echo "Creating new list list..."

	modification_time="%TY-%Tm-%Td %TH:%TM:%TS"
	full_path="$_WORKSPACE/$_FILE_NAME"

	set +e

	find / \( -perm $_PERM \) \
		-type f \
		-fprintf "$full_path" "%p ${modification_time}\n"  \
		2>/dev/null
	set -e

	count="$(wc -l "$full_path" | awk '{print $1}')"

	echo "List was created at $full_path"
	echo "Found ($count) elements for $_DISPLAY_MODE"
}

get_diff() {
	if [[ ! -f "$_PREVIOUS_FILE" ]]; then
		echo "No diff to show because their is no previous list available"
		return
	fi

	echo "Comparing $(basename $_PREVIOUS_FILE) to $_FILE_NAME"

	set +e
	diff="$(diff "$_PREVIOUS_FILE" "$_WORKSPACE/$_FILE_NAME")"
	set -e

	if [[ -n "$diff" ]]; then
		echo "Warning ! Their is differences among the 2 files !"
		echo "$diff"
	else
		echo "The two files are identical"
	fi
}

main() {
	_SHOW_SUID="n"
	_SHOW_SGID="n"
	_DISPLAY_MODE=""
	_WORKSPACE="/var/tmp/$(basename "$0")"
	_FILE_NAME=""
	_PREVIOUS_FILE=""
	_PERM=""

	init
	check_args "$@"
	set_mode
	set_workspace
	set_previous_file
	create_list
	get_diff
}

main "$@"
