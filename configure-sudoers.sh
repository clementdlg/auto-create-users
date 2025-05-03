#!/usr/bin/env bash

set -euo pipefail

# for logging
green="\e[32m"
yellow="\e[33m"
red="\e[31m"
purple="\033[95m"
reset="\e[0m"

# globals
_LOGFILE=/tmp/configure-sudo.log
_CONFIG_FILE=""

# utils
end_function='log i "${FUNCNAME[0]} : success"'

log() {
    msg="$2"
    [[ -n "$msg" ]]

    timestamp="[$(date +%H:%M:%S)]"

    label=""
    case "$1" in
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
        return 1
    fi

    echo "" > "$_LOGFILE"
}

check_args() {
    if [[ $# -ne 1 ]]; then
        log i "Usage: $0 <file>"
        log i "<file>  : A file containing sudo configuration (one user per line) with this format:"
        log i "login:machine(s):command1,mode@command2,mode@command3,mode..."
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

    _CONFIG_FILE="$1"
}

not_empty() {
	if [[ -z "$1" ]]; then
		log e "Empty field in file !"
		return 1
	fi
}

validate_fields() {
    local fields_nr="$(echo "$line" | awk -F: '{print NF}')"
    if [[ $fields_nr -ne 3 ]]; then
        log e "Line $line_nr: Invalid number of fields"
        return 1
    fi

    _LOGIN="$(echo "$line" | cut -f1 -d:)"
    _HOSTS="$(echo "$line" | cut -f2 -d:)"
    _COMMANDS="$(echo "$line" | cut -f3 -d:)"

	not_empty "$_LOGIN"
	not_empty "$_HOSTS"
	not_empty "$_COMMANDS"

	eval "$end_function"
}

validate_command_fields() {
	current="$1"
	cmd_fields_nr="$(echo "$current" | awk -F, '{print NF}')"

	if [[ "$cmd_fields_nr" -ne 2 ]]; then
		log e "Invalid format for '$current'"
		return 1
	fi
}

validate_cmd() {
	cmd="$1"

	local fields_nr="$(echo "$cmd" | awk '{print NF}')"

	if [[ "$fields_nr" -gt 1 ]]; then
		cmd="$(echo "$cmd" | awk '{print $1}')"
	fi

	if ! [[ "$cmd" == "ALL" || -n "$(command -v "$cmd")" ]]; then
		log e "The command '$cmd' does not exist on the system"
		return 1
	fi
}

validate_mode() {
	mode="$1"

	if [[ "$mode" != "nopasswd" && "$mode" != "passwd" ]]; then
		log e "Mode '$mode' is invalid"
		return 1
	fi

	if [[ "$mode" == "nopasswd" ]]; then
		_PASSWD="n"
	fi
}

validate_commands() {

	local fields_nr="$(echo "$_COMMANDS" | awk -F@ '{print NF}')"

	for i in $(seq 1 $fields_nr); do
		current="$(echo "$_COMMANDS" | cut -d@ -f$i)"

		validate_command_fields "$current"

		cmd="$(echo "$current" | cut -d, -f1)"
		mode="$(echo "$current" | cut -d, -f2)"

		validate_cmd "$cmd"
		validate_mode "$mode"
	done

	eval "$end_function"
}

validate_login() {
	if groups "$_LOGIN" | grep -q -E '\b(sudo|wheel)\b'; then
        return 0
    fi

	if sudo -lU "$_LOGIN" | grep -q '(ALL)'; then
		return 0
	fi

	log e "User exists, but is not sudoers"
	return 1
}

write_to_sudoers_file() {
	line="$1"
	echo "$line" | EDITOR='tee -a' visudo
}

create_machine_alias() {
    hosts_nr="$(echo "$_HOSTS" | awk -F, '{print NF}')"

	if [[ "$hosts_nr" -eq 1 ]]; then
		_ALIAS_NAME="$_HOSTS"
		return
	fi

	# Host_Alias CDELON_HOSTS = buroprofs,dpmoc
	_ALIAS_NAME="${_LOGIN^^}_HOSTS"
	alias="Host_Alias ${_ALIAS_NAME} = ${_HOSTS}"

	if grep -q "Host_Alias ${_ALIAS_NAME}" /etc/sudoers; then
		log i "Alias ${_ALIAS_NAME} already exists. Skipping"
		return
	fi

	write_to_sudoers_file "$alias"
}

set_cmd_path() {	
	cmd="$1" # rm -r *

	local fields_nr="$(echo "$cmd" | awk '{print NF}')" # 3

	if [[ "$fields_nr" -gt 1 ]]; then
		base_cmd="$(echo "$cmd" | awk '{print $1}')"
		_CMD_ARGS="${cmd#"$base_cmd "}"
		_CMD_PATH="$base_cmd"
		cmd="$base_cmd"
	fi

	if [[ ! -f "$cmd" && "$cmd" != "ALL" ]]; then
		_CMD_PATH="$(which "$cmd")"
	fi
}

set_cmd_string() {
	local fields_nr="$(echo "$_COMMANDS" | awk -F@ '{print NF}')"

	for i in $(seq 1 $fields_nr); do
		current="$(echo "$_COMMANDS" | cut -d@ -f$i)"

		cmd="$(echo "$current" | cut -d, -f1)"
		mode="$(echo "$current" | cut -d, -f2)"

		_CMD_PATH="$cmd"
		_CMD_ARGS=""
		ending=", "

		if [[ "$_PASSWD" == "n" ]]; then
			_CMD_STRING="${_CMD_STRING}NOPASSWD: "
		fi

		set_cmd_path "$cmd"

		if (( i == fields_nr )); then
			ending=""
		fi

		_CMD_STRING="${_CMD_STRING}${_CMD_PATH} ${_CMD_ARGS}${ending}"
	done

}

configure_sudoers() {
	#  esgi ALL=(root) /usr/sbin/shutdown, NOPASSWD: /usr/sbin/reboot
	if grep -q "^${_LOGIN}" /etc/sudoers; then
		log i "User entree for ${_LOGIN} already exists. Skipping"
		return
	fi

	write_to_sudoers_file "${_LOGIN} ${_ALIAS_NAME}=(root) ${_CMD_STRING}"
}

main() {
    init
    check_args "$@"

    line_nr=0

    while IFS= read -r line; do
        line_nr=$((line_nr+1))

        log i "Processing line $line_nr"

		_LOGIN=""
		_HOSTS=""
		_COMMANDS=""
		_PASSWD="y"
		_ALIAS_NAME=""
		_CMD_STRING=""

        validate_fields "$line"
		validate_login "$_LOGIN"
        validate_commands "$line"

		
        create_machine_alias
		set_cmd_string
        configure_sudoers
		
    done < "$_CONFIG_FILE"

    log i "Sudo configuration has finished successfully"
}

main "$@"
