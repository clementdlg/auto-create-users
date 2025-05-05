#!/usr/bin/env bash

set -euo pipefail

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

main() {
	_SHOW_SUID="n"
	_SHOW_SGID="n"

	check_args "$@"
	show_info
}

main "$@"
