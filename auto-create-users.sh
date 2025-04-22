#!/usr/bin/env bash

set -euo pipefail

# for logging
green="\e[32m"
yellow="\e[33m"
red="\e[31m"
purple="\033[95m"
reset="\e[0m"

# globals
_LOGFILE=/tmp/auto-create-users.log
_USER_FILE=""

# utils
end_function='log i "${FUNCNAME[0]} : success"'

log() {
	msg="$2"
	[[ -n "$msg" ]]

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
		log x "Run this script as root"
		return 1
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
		log i "<file>  : A file containing user data (one user per line) with this format :"
		log i "name:surname:group1,group2,...:sudo:package1/package2/...:password"
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
	eval "$end_function"
}

validate_simple_fields() {

	# must have 6 fields
	fields_nr="$(echo "$line" | awk -F: '{print NF}')"
	if [[ $fields_nr -ne 6 ]]; then
		log e "Line $line_nr: Invalid number of fields"
		return 1
	fi

	_NAME="$(echo "$line" | cut -f1 -d:)"
	not_empty "$_NAME"
	valid_charset "$_NAME"

	_SURNAME="$(echo "$line" | cut -f2 -d:)"
	not_empty "$_SURNAME"
	valid_charset "$_SURNAME"

	_PASSWORD="$(echo "$line" | cut -f6 -d:)"
	not_empty "$_PASSWORD"

	sudo_value="$(echo "$line" | cut -d: -f4)"
	if [[ "$sudo_value" != "oui" && "$sudo_value" != "non" ]]; then
		log e "Sudo value can either be set to 'oui' or 'non'. Got '$sudo_value' instead"
		return 1
	fi

	eval "$end_function"
}

validate_group() {
	if [[ -z "$1" ]]; then
		_CREATE_PRIMARY_GROUP=y
		return
	fi

	group="$1"
	fields_nr="$(echo "$group" | awk -F, '{print NF}')"
	_GROUP_NR=$fields_nr

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

	eval "$end_function"
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

	eval "$end_function"
}

create_group() {
	log d "_CREATE_PRIMARY_GROUP = $_CREATE_PRIMARY_GROUP"
	log d "_CREATE_ADDITIONAL_GROUP = $_CREATE_ADDITIONAL_GROUP"

	[[ "$_CREATE_PRIMARY_GROUP" == "y" ]] && return

	
	group="$1"
	fields_nr="$(echo "$group" | awk -F, '{print NF}')"

	for i in $(seq 1 $fields_nr); do
		current="$(echo "$group" | cut -d, -f$i)"

		if getent group "$current" &>/dev/null; then
			continue;
		fi

		groupadd "$current"
	done

	eval "$end_function"
}

create_user() {
	# -c "comment"
	# -g primary group
	# -G "group1,group2"
	# -m create home dir
	# -p password
	# -U create groups same as username
	log d "name = $_NAME"
	log d "surname = $_SURNAME"
	log d "password = $_PASSWORD"
	log d "group = $_GROUP"

	primary="$(echo $_GROUP | cut -d, -f1)"
	other_groups="$(echo $_GROUP | sed "s/$primary,//")"

	username="${_NAME:0:1}$_SURNAME"
	# while grep "$username" /etc/passwd; do
	# 	
	# done

	case $_GROUP_NR in
		0)
		useradd -c "$_NAME $_SURNAME" \
				-p "$_PASSWORD" \
				-U \
				-m \
				"$username"
				;;
		1)
		useradd -c "$_NAME $_SURNAME" \
				-p "$_PASSWORD" \
				-g "$_GROUP" \
				-m \
				"$username"
				;;
		*)
		useradd -c "$_NAME $_SURNAME" \
				-p "$_PASSWORD" \
				-g "$primary" \
				-G "$other_groups" \
				-m \
				"$username"
				;;
		esac
	eval "$end_function"
}

main() {
	init
	check_args "$@"

	line_nr=0

	# process each line from the file
	while IFS= read -r line; do
		_CREATE_PRIMARY_GROUP=n
		_CREATE_ADDITIONAL_GROUP=n
		_INSTALL_PACKAGES=n
		_NAME=""
		_SURNAME=""
		_GROUP=""
		_GROUP_NR=0
		_PASSWORD=""

		line_nr=$((line_nr+1))

		log i "Processing line $line_nr"

		validate_simple_fields "$line"

		_GROUP="$(echo "$line" | cut -f3 -d:)"
		validate_group "$_GROUP"
		
		packages="$(echo "$line" | cut -f5 -d:)"
		validate_packages "$packages"

		create_group "$group"
		create_user
		# install_packages


	done < "$_USER_FILE"

	eval "$end_function"
}

main "$@"
