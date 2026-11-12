#!/usr/bin/env bash
# Install the CachyOS restore package list with pacman.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf 'Run this script directly; do not source it.\n' >&2
    return 1
fi
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_dir=$(cd -- "$script_dir/../.." && pwd -P)
source "$project_dir/lib/common.sh"
file=$project_dir/packages/system.txt
dry_run=false
install_nvidia=true
while (( $# )); do
    case "$1" in
        --file) (( $# >= 2 )) && [[ -n $2 ]] || restore_die '--file requires a path.'; file=$2; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --skip-nvidia) install_nvidia=false; shift ;;
        --help|-h) printf 'Usage: %s [--file PATH] [--skip-nvidia] [--dry-run]\n' "$0"; exit 0 ;;
        *) restore_die "Unknown argument: $1" ;;
    esac
done
restore_require_user
restore_require_cachyos
restore_read_list "$file" packages pacman
required_packages=(zsh xdg-user-dirs)
$install_nvidia && required_packages+=(chwd)
for required_package in "${required_packages[@]}"; do
    if [[ ! " ${packages[*]} " == *" $required_package "* ]]; then
        packages+=("$required_package")
    fi
done
if (( ${#packages[@]} )) && ! $dry_run; then
    command -v pacman >/dev/null 2>&1 || restore_die 'pacman is required.'
    command -v sudo >/dev/null 2>&1 || restore_die 'sudo is required.'
fi
# Refresh and upgrade together to avoid a partial upgrade on Arch-based systems.
if (( ${#packages[@]} )); then
    restore_run sudo pacman -Syu --needed -- "${packages[@]}"
fi

if $install_nvidia; then
    if $dry_run; then
        printf 'Would detect NVIDIA graphics hardware and request the proprietary 580xx chwd profile if present.\n'
    else
        nvidia_found=false
        for device in /sys/bus/pci/devices/*; do
            [[ -r $device/vendor && -r $device/class ]] || continue
            read -r vendor < "$device/vendor"
            read -r class < "$device/class"
            if [[ $vendor == 0x10de && ( $class == 0x0300* || $class == 0x0302* || $class == 0x0380* ) ]]; then
                nvidia_found=true
                break
            fi
        done
        if $nvidia_found; then
            command -v chwd >/dev/null 2>&1 || restore_die 'chwd is missing after package installation.'
            profile=nvidia-dkms-580xx
            if [[ -r /sys/class/dmi/id/chassis_type ]]; then
                read -r chassis_type < /sys/class/dmi/id/chassis_type
                case "$chassis_type" in 8|9|10|11|31) profile+=.prime ;; esac
            fi
            printf 'Installing the proprietary NVIDIA driver using chwd profile %s.\n' "$profile"
            sudo chwd -i "$profile" || restore_die 'NVIDIA driver installation failed; check chwd output and GPU compatibility.'
            printf 'Reboot after the restore to load the NVIDIA driver.\n'
        else
            printf 'No NVIDIA graphics device detected; skipping NVIDIA driver installation.\n'
        fi
    fi
fi

# Read the account database instead of $SHELL, which may describe an old session.
if $dry_run; then
    printf 'Would set the current user’s login shell to /usr/bin/zsh if needed.\n'
else
    [[ -x /usr/bin/zsh ]] || restore_die 'Zsh is missing after package installation.'
    command -v getent >/dev/null 2>&1 || restore_die 'getent is required to inspect the login shell.'
    account=$(getent passwd "$(id -u)") || restore_die 'Could not look up the current user.'
    username=${account%%:*}
    current_shell=${account##*:}
    [[ -n $username && -n $current_shell ]] || restore_die 'Could not determine the current login shell.'
    if [[ $current_shell == /usr/bin/zsh ]]; then
        printf 'Zsh is already the login shell.\n'
    else
        sudo chsh -s /usr/bin/zsh "$username"
        printf 'Login shell set to Zsh; it will be used in new login sessions.\n'
    fi
fi

restore_setup_path
if $dry_run; then
    printf 'Would install Proton Pass CLI using the official installer if pass-cli is missing.\n'
elif command -v pass-cli >/dev/null 2>&1; then
    printf 'Proton Pass CLI is already available.\n'
else
    command -v curl >/dev/null 2>&1 || restore_die 'curl is required to install Proton Pass CLI.'
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/restore-pass-cli.XXXXXXXX")
    trap 'rm -rf -- "$temp_dir"' EXIT
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --output "$temp_dir/install.sh" https://proton.me/download/pass-cli/install.sh
    PROTON_PASS_CLI_INSTALL_DIR="$HOME/.local/bin" bash "$temp_dir/install.sh"
    command -v pass-cli >/dev/null 2>&1 || restore_die 'Proton Pass CLI installation did not put pass-cli on PATH.'
fi
