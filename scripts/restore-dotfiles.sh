#!/usr/bin/env bash
# Restore chezmoi dotfiles using an age identity stored in Proton Pass.

if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf 'Run this script directly; do not source it.\n' >&2
    return 1
fi

# Never trace commands that handle secrets, even when invoked with bash -x.
set +x
set -Eeuo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage: ./scripts/restore-dotfiles.sh [--replace-key] [--self-destruct] [--help]

Fetch and validate the age identity from Proton Pass, then run chezmoi init --apply.

  --replace-key    Allow replacing a different existing identity.
  --self-destruct  Delete this script only after a successful restore.
  --help          Show this help without making changes.

Environment overrides:
  REPO_URL                   Default: https://github.com/Palpatraz02/dotfiles.git
  PROTON_PASS_AGE_KEY_REF     Full pass://vault/item/field reference (takes priority)
  PROTON_PASS_VAULT          Default: Personal
  PROTON_PASS_AGE_KEY_ITEM    Default: Chezmoi Age Master Key
  PROTON_PASS_AGE_KEY_FIELD   Default: note
  XDG_CONFIG_HOME            Default: $HOME/.config

Install bash, git, chezmoi, age, and Proton Pass CLI before running.
Run as your normal user. The repository must configure chezmoi to use this identity.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

replace_key=false
self_destruct=false
for arg in "$@"; do
    case "$arg" in
        --replace-key) replace_key=true ;;
        --self-destruct) self_destruct=true ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown argument: $arg (see --help)" ;;
    esac
done

[[ ${HOME:-} == /* ]] || die 'HOME must be an absolute path.'
[[ $EUID -ne 0 ]] || die 'Run as your normal user, without sudo.'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_dir=$(cd -- "$script_dir/.." && pwd -P)
source "$project_dir/lib/common.sh"
restore_setup_path

repo_url=${REPO_URL:-https://github.com/Palpatraz02/dotfiles.git}
key_ref=${PROTON_PASS_AGE_KEY_REF:-pass://${PROTON_PASS_VAULT:-Personal}/${PROTON_PASS_AGE_KEY_ITEM:-Chezmoi Age Master Key}/${PROTON_PASS_AGE_KEY_FIELD:-note}}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
[[ $config_home == /* ]] || die 'XDG_CONFIG_HOME must be an absolute path.'
[[ $key_ref == pass://*/*/* && $key_ref != */ ]] ||
    die 'Use a pass://vault/item/field reference, including the field containing the key.'

missing=()
for dependency in git chezmoi age pass-cli mktemp mkdir chmod mv rm rmdir cmp dirname basename; do
    command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
done
(( ${#missing[@]} == 0 )) || die "Missing dependencies: ${missing[*]}"

script_path=''
if $self_destruct; then
    script_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")
fi

config_dir=$config_home/chezmoi
key_path=$config_dir/key.txt
lock_dir=$config_dir/.restore.lock
temp_key=''
lock_held=false

cleanup() {
    [[ -z $temp_key ]] || rm -f -- "$temp_key"
    if $lock_held; then
        rmdir -- "$lock_dir"
    fi
    return 0
}
trap cleanup EXIT
trap 'printf "Error: restore failed at line %s (exit %s).\n" "$LINENO" "$?" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf 'Preparing secure chezmoi configuration...\n'
[[ ! -L $config_dir ]] || die "Refusing a symlinked configuration directory: $config_dir"
mkdir -p -- "$config_dir"
chmod 700 -- "$config_dir"
if ! mkdir -- "$lock_dir" 2>/dev/null; then
    die "Cannot acquire $lock_dir. If an earlier run was interrupted, remove this empty directory after checking no restore is running."
fi
lock_held=true

[[ ! -L $key_path ]] || die "Refusing a symlinked identity: $key_path"
[[ ! -e $key_path || -f $key_path ]] || die "Identity path is not a regular file: $key_path"

printf 'Checking Proton Pass authentication...\n'
if ! pass-cli info >/dev/null 2>&1; then
    printf 'Log in using the Proton Pass authentication flow...\n'
    pass-cli login
fi
pass-cli info >/dev/null 2>&1 || die 'Could not establish a Proton Pass session.'

printf 'Fetching and validating the age identity...\n'
# Keep the secret out of shell variables and command arguments. Force field output
# to human/plain text even if the user configured JSON as the CLI default.
temp_key=$(mktemp "$config_dir/.key.txt.XXXXXXXX")
chmod 600 -- "$temp_key"
if ! pass-cli item view --output human "$key_ref" >"$temp_key"; then
    die 'Could not retrieve the age identity from Proton Pass.'
fi
[[ -s $temp_key ]] || die 'Proton Pass returned an empty identity.'
# Encrypting empty input validates the identity without printing it or requiring
# a separate age-keygen binary. Suppress parser diagnostics containing key data.
if ! age --encrypt --identity "$temp_key" </dev/null >/dev/null 2>&1; then
    die 'The selected field is not a usable, unencrypted age identity.'
fi

if [[ -f $key_path ]] && cmp -s -- "$temp_key" "$key_path"; then
    chmod 600 -- "$key_path"
    rm -f -- "$temp_key"
elif [[ -e $key_path ]] && ! $replace_key; then
    die 'An existing identity differs. Verify the vault entry, then use --replace-key if replacement is intended.'
else
    # The temporary file is on the same filesystem: rename installs it atomically.
    mv -f -- "$temp_key" "$key_path"
fi
temp_key=''

printf 'Identity ready at %s\n' "$key_path"
printf 'Initializing and applying chezmoi configuration...\n'
chezmoi init --apply -- "$repo_url"
printf 'Restore completed successfully.\n'

if $self_destruct; then
    rm -- "$script_path"
    printf 'Removed the restore script.\n'
fi
