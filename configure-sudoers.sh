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
    fields_nr="$(echo "$line" | awk -F: '{print NF}')"
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

	fields_nr="$(echo "$cmd" | awk '{print NF}')"

	if [[ "$fields_nr" -gt 1 ]]; then
		cmd="$(echo "$cmd" | awk '{print $1}')"
	fi

	_BASE_CMD="$cmd"

	if ! [[ "$cmd" == "ALL" || -x "$(command -v "$cmd")" ]]; then
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
}

validate_commands() {

	fields_nr="$(echo "$_COMMANDS" | awk -F@ '{print NF}')"

	for i in $(seq 1 $fields_nr); do
		current="$(echo "$_COMMANDS" | cut -d@ -f$i)"

		log d "validating '$current'"

		validate_command_fields "$current"

		cmd="$(echo "$current" | cut -d, -f1)"
		mode="$(echo "$current" | cut -d, -f2)"

		log d "cmd = $cmd"
		log d "mode = $mode"

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

# append_path_to_cmd() {
#
# }

# create_machine_alias() {
#     machines_list=$(echo "$_HOSTS" | tr ',' '\n')
#     alias_name=$(echo "$_HOSTS" | tr ',' '_')
#     alias_exists=$(grep -q "Cmnd_Alias $alias_name" /etc/sudoers)
#
#     if [[ -z "$alias_exists" ]]; then
#         echo "Cmnd_Alias $alias_name = $machines_list" >> /etc/sudoers
#         log i "Created machine alias for $_LOGIN: $alias_name"
#     else
#         log i "Machine alias for $_LOGIN already exists: $alias_name"
#     fi
# }
#
# configure_sudoers() {
#     sudoers_file="/etc/sudoers"
#
#     # Verify user is a sudoer
#     if ! id "$_LOGIN" &>/dev/null; then
#         log e "User $_LOGIN does not exist, skipping."
#         return
#     fi
#
#     log i "Configuring sudo for $_LOGIN"
#
#     # Add the user to sudoers
#     for cmd in $(echo "$_COMMANDS" | tr ',' '\n'); do
#         command=$(echo "$cmd" | cut -f1 -d@)
#         mode=$(echo "$cmd" | cut -f2 -d@)
#
#         # Check if the command is full path or relative
#         if ! command -v "$command" &>/dev/null; then
#             log e "Command '$command' not found, skipping."
#             continue
#         fi
#
#         log i "Granting $_LOGIN $mode access to $command on $alias_name"
#
#         if [[ "$mode" == "nopasswd" ]]; then
#             echo "$_LOGIN $alias_name=$command NOPASSWD: ALL" >> /etc/sudoers
#         else
#             echo "$_LOGIN $alias_name=$command" >> /etc/sudoers
#         fi
#     done
# }

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
		_BASE_CMD=""

		_HOST_NEEDS_ALIAS="n"

        validate_fields "$line"
		validate_login "$_LOGIN"
        validate_commands "$line"

        # create_machine_alias
        # configure_sudoers
    done < "$_CONFIG_FILE"

    log i "Sudo configuration has finished successfully"
}

main "$@"
