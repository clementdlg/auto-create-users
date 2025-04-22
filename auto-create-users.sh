#!/usr/bin/env bash

set -euo pipefail

green="\e[32m"
yellow="\e[33m"
red="\e[31m"
purple="\033[95m"
reset="\e[0m"

_LOGFILE=/tmp/auto-create-users.log
_USER_FILE=""
_CREATE_PRIMARY_GROUP=n
_CREATE_ADDITIONAL_GROUP=n
_INSTALL_PACKAGES=n

log() {
	msg="$2"
	[[ ! -z "$msg" ]]

	timestamp="[$(date +%H:%M:%S)]"

	label=""
	case "$1" in
		# c) label="[CLEANUP]" ; color="$yellow" ;;
		e) label="[ERROR]" ; color="$red" ;;
		x) label="[EXIT]" ; color="$yellow" ;;
		d) label="[DEBUG]" ; color="$purple" ;;
		i) label="[INFO]" ; color="$green" ;;
	esac

	log="$timestamp$color$label$reset $msg "
	echo -e "$log"

	log="$timestamp$label $msg "

	if [[ -f ${_LOGFILE} ]]; then
		echo "$log" >> ${_LOGFILE}
	fi
}

init() {
	if [[ $EUID -ne 0 ]]; then
		log e "Run this script as root"
	fi

	echo "" > "$_LOGFILE"
}

not_empty() {
	if [[ -z "$1" ]]; then
		log e "Empty value"
		return 1
	fi
}

valid_charset() {
	[[ -z "$1" ]] && return 1
	allowed_chars="^[a-zA-Z0-9_-é]+$"

	if [[ ! "$1" =~ $allowed_chars ]]; then
		log e "Invalid charset"
		return 1
	fi
}

check_args() {
	if [[ $# -ne 1 ]]; then
		log i "Usage: $0 <file>"
		log i "  <file>  : A file containing user data (one user per line)"
		return 1
	fi

	if [[ ! -f "$1" ]]; then
		log e "$1 is not a file"
		return 1
	fi

	if [[ ! -s "$1" ]]; then
		log e "$1 is empty"
		return 1
	fi

	_USER_FILE="$1"
	log i "${FUNCNAME[0]} : success"
}

validate_group() {
	if [[ -z "$1" ]]; then
		_CREATE_PRIMARY_GROUP=y
		return
	fi

	group="$1"
	fields_nr="$(echo "$group" | awk -F, '{print NF}')"

	# if only primary group
	if [[ $fields_nr -eq 1 ]]; then
		valid_charset "$group"
		return
	fi

	_CREATE_ADDITIONAL_GROUP=y

	for i in $(seq 1 $fields_nr); do
		current="$(echo "$group" | cut -d, -f$i)"
		not_empty "$current"
		valid_charset "$current"
	done
}

validate_packages() {
	if [[ -z "$1" ]]; then
		return
	fi

	_INSTALL_PACKAGES=y

	packages="$1"
	fields_nr="$(echo "$packages" | awk -F/ '{print NF}')"

	for i in $(seq 1 $fields_nr); do
		current="$(echo "$packages" | cut -d/ -f$i)"
		not_empty "$current"
	done
}

validate_format() {
	line_nr=0

	while IFS= read -r line; do
		line_nr=$((line_nr+1))

		# must have 6 fields
		fields_nr="$(echo "$line" | awk -F: '{print NF}')"
		if [[ $fields_nr -ne 6 ]]; then
			log e "Line $line_nr: Invalid number of fields"
			return 1
		fi

		log i "Validating name"
		name="$(echo $line | cut -f1 -d:)"
		not_empty "$name"
		valid_charset "$name"

		log i "Validating surname"
		surname="$(echo $line | cut -f2 -d:)"
		not_empty "$surname"
		valid_charset "$surname"

		log i "Validating password"
		password="$(echo $line | cut -f6 -d:)"
		not_empty "$password"

		log i "Validating sudo"
		sudo_value="$(echo $line | cut -d: -f4)"
		if [[ "$sudo_value" != "oui" && "$sudo_value" != "non" ]]; then
			log e "Sudo value can either be set to 'oui' or 'non'. Got '$sudo_value' instead"
			return 1
		fi

		log i "Validating groups"
		group="$(echo $line | cut -f3 -d:)"
		validate_group "$group"
		
		log i "Validating packages"
		packages="$(echo $line | cut -f5 -d:)"
		validate_packages "$packages"

	done < "$_USER_FILE"

	log i "${FUNCNAME[0]} : success"
}

main() {
	init
	check_args "$@"
	validate_format
	log i "${FUNCNAME[0]} : success"
}

main "$@"
