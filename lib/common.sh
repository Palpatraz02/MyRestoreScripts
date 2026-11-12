#!/usr/bin/env bash
# Shared helpers; sourcing this file does not change the host system.

restore_die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

restore_require_user() {
    [[ $EUID -ne 0 ]] || restore_die 'Run as your normal user, without sudo.'
    [[ ${HOME:-} == /* ]] || restore_die 'HOME must be an absolute path.'
}

restore_setup_path() {
    export PATH="$HOME/.local/bin:$PATH"
}

restore_require_cachyos() {
    local ID=''
    local os_release=${RESTORE_OS_RELEASE_FILE:-/etc/os-release}
    [[ -r $os_release ]] || restore_die 'Cannot read os-release.'
    source "$os_release"
    [[ $ID == cachyos ]] || restore_die 'This restore targets CachyOS.'
}

restore_read_list() {
    local file=$1 kind=$3 line number=0 pattern
    local -n output=$2
    local -A seen=()
    output=()
    [[ -f $file && -r $file ]] || restore_die "Cannot read list: $file"
    case "$kind" in
        pacman) pattern='^[[:alnum:]][[:alnum:]_.+-]*$' ;;
        service) pattern='^[[:alnum:]][[:alnum:]@_.:-]*\.service$' ;;
        *) restore_die "Unknown list type: $kind" ;;
    esac
    while IFS= read -r line || [[ -n $line ]]; do
        (( number += 1 ))
        line=${line%$'\r'}
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -n $line ]] || continue
        [[ $line =~ $pattern ]] || restore_die "Invalid $kind entry at $file:$number."
        [[ -z ${seen[$line]:-} ]] || continue
        seen[$line]=1
        output+=("$line")
    done <"$file"
}

restore_run() {
    if $dry_run; then
        printf 'Would run: '; printf '%q ' "$@"; printf '\n'
    else
        "$@"
    fi
}
