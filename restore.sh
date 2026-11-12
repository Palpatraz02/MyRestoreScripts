#!/usr/bin/env bash
# Install packages, restore dotfiles, then configure services and Git.

if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf 'Run this script directly; do not source it.\n' >&2
    return 1
fi

set +x
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./restore.sh [OPTIONS]

Restore CachyOS: pacman packages, dotfiles, services, and Git.

  --packages-file PATH         Override packages/system.txt.
  --dry-run                   Preview all selected steps without changes.
  --skip-packages             Skip package installation.
  --skip-nvidia               Skip NVIDIA driver installation.
  --skip-dotfiles             Skip the chezmoi restore.
  --skip-config               Skip service and Git configuration.
  --services-file PATH        Use a different list of services for configuration.
  --git-name NAME             Override the default Git author name.
  --git-email EMAIL           Override the default Git author email.
  --skip-services             Skip services in the configuration step.
  --skip-git                  Skip Git in the configuration step.
  --replace-key               Allow replacing a different existing age identity.
  --self-destruct             Remove this launcher after all selected steps succeed.
  --help                      Show help without making changes.

Run as your normal user. Package installation requests privileges when needed.
Proton Pass CLI is installed with Proton’s official installer when missing.
The package step installs Zsh and sets it as the current user's login shell.
See README.md for dotfiles environment overrides.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
script_path=$script_dir/$(basename -- "${BASH_SOURCE[0]}")
package_args=()
dry_run=false
install_packages=true
restore_dotfiles=true
configure_system=true
self_destruct=false
dotfiles_args=()
config_args=()

while (( $# )); do
    case "$1" in
        --packages-file)
            (( $# >= 2 )) && [[ -n $2 ]] || die "$1 requires a path."
            package_args+=(--file "$2")
            shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --skip-packages) install_packages=false; shift ;;
        --skip-nvidia) package_args+=(--skip-nvidia); shift ;;
        --skip-dotfiles) restore_dotfiles=false; shift ;;
        --skip-config) configure_system=false; shift ;;
        --services-file|--git-name|--git-email)
            (( $# >= 2 )) && [[ -n $2 ]] || die "$1 requires a value."
            config_args+=("$1" "$2")
            shift 2
            ;;
        --skip-services|--skip-git) config_args+=("$1"); shift ;;
        --replace-key) dotfiles_args+=(--replace-key); shift ;;
        --self-destruct) self_destruct=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ $EUID -ne 0 ]] || die 'Run as your normal user, without sudo.'
[[ ${HOME:-} == /* ]] || die 'HOME must be an absolute path.'
source "$script_dir/lib/common.sh"
restore_require_cachyos
restore_setup_path
if ! $install_packages && ! $restore_dotfiles && ! $configure_system; then
    die 'All steps were skipped; there is nothing to restore.'
fi

# Check selected scripts before starting any step.
if $install_packages; then
    [[ -r $script_dir/scripts/install/install-packages.sh ]] || die 'Missing install-packages.sh.'
fi
if $restore_dotfiles; then
    [[ -r $script_dir/scripts/restore-dotfiles.sh ]] || die 'Missing restore-dotfiles.sh.'
fi
if $configure_system; then
    [[ -r $script_dir/scripts/configure-system.sh ]] || die 'Missing configure-system.sh.'
fi

preview_args=()
$dry_run && preview_args+=(--dry-run)
if $install_packages; then
    bash "$script_dir/scripts/install/install-packages.sh" "${package_args[@]}" "${preview_args[@]}"
fi
if $restore_dotfiles; then
    if $dry_run; then
        printf 'Would run: bash %q ' "$script_dir/scripts/restore-dotfiles.sh"
        if (( ${#dotfiles_args[@]} )); then
            printf '%q ' "${dotfiles_args[@]}"
        fi
        printf '\n'
    else
        bash "$script_dir/scripts/restore-dotfiles.sh" "${dotfiles_args[@]}"
    fi
fi
if $configure_system; then
    bash "$script_dir/scripts/configure-system.sh" "${config_args[@]}" "${preview_args[@]}"
fi

if $dry_run; then
    printf 'Preview completed; no restore changes were made.\n'
else
    printf 'All selected restore steps completed successfully.\n'
fi
if $self_destruct && ! $dry_run; then
    rm -- "$script_path"
    printf 'Removed the restore launcher.\n'
fi
