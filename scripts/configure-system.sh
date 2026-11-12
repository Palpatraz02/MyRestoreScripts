#!/usr/bin/env bash
# Start restored system services and configure the current user's Git identity.

if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf 'Run this script directly; do not source it.\n' >&2
    return 1
fi

set +x
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./scripts/configure-system.sh [OPTIONS]

  --services-file PATH  Use a different list of systemd services.
  --git-name NAME       Git author name (default: Fabien Dufour).
  --git-email EMAIL     Git author email (default: github@id.fabyd.dev).
  --skip-services       Configure only Git.
  --skip-git            Configure only services.
  --dry-run             Show commands without making changes.
  --help                Show this help.

Docker and tailscaled are enabled at boot and started. Other services, including
cloudflared, are started using their existing configuration. No accounts are
authenticated, tunnel credentials replaced, or group memberships changed.
RESTORE_GIT_NAME and RESTORE_GIT_EMAIL can override the default Git identity.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_dir=$(cd -- "$script_dir/.." && pwd -P)
services_file=$project_dir/config/services.txt
git_name=${RESTORE_GIT_NAME:-Fabien Dufour}
git_email=${RESTORE_GIT_EMAIL:-github@id.fabyd.dev}
configure_services=true
configure_git=true
dry_run=false

while (( $# )); do
    case "$1" in
        --services-file|--git-name|--git-email)
            (( $# >= 2 )) && [[ -n $2 ]] || die "$1 requires a value."
            case "$1" in
                --services-file) services_file=$2 ;;
                --git-name) git_name=$2 ;;
                --git-email) git_email=$2 ;;
            esac
            shift 2
            ;;
        --skip-services) configure_services=false; shift ;;
        --skip-git) configure_git=false; shift ;;
        --dry-run) dry_run=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ $EUID -ne 0 ]] || die 'Run as your normal user, without sudo.'
[[ ${HOME:-} == /* ]] || die 'HOME must be an absolute path.'
if ! $configure_services && ! $configure_git; then
    die 'Both configuration steps were skipped.'
fi

source "$project_dir/lib/common.sh"
restore_require_cachyos
restore_setup_path

services=()
declare -A seen=()
if $configure_services; then
    [[ -f $services_file && -r $services_file ]] || die "Cannot read service list: $services_file"
    line_number=0
    while IFS= read -r line || [[ -n $line ]]; do
        (( line_number += 1 ))
        line=${line%$'\r'}
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -n $line ]] || continue
        [[ $line =~ ^[[:alnum:]][[:alnum:]@_.:-]*\.service$ ]] ||
            die "Invalid service at $services_file:$line_number. Use a complete .service unit name."
        [[ -z ${seen[$line]:-} ]] || continue
        seen[$line]=1
        services+=("$line")
    done <"$services_file"
fi

if $configure_git; then
    [[ $git_name =~ [^[:space:]] && $git_name != *$'\n'* && $git_name != *$'\r'* ]] || die 'Git author name must be a nonempty single line.'
    [[ $git_email == ?*@?* && $git_email != *[[:space:]]* ]] || die 'Git author email must contain @ and no whitespace.'
fi

if ! $dry_run; then
    if $configure_git; then
        command -v git >/dev/null 2>&1 || die 'git is missing. Run install-packages.sh first.'
    fi
    if (( ${#services[@]} )); then
        command -v systemctl >/dev/null 2>&1 || die 'systemctl is required.'
        command -v sudo >/dev/null 2>&1 || die 'sudo is required for system service configuration.'
        # Validate every unit before starting any service or writing Git settings.
        for service in "${services[@]}"; do
            if ! state=$(systemctl show --property=LoadState --value "$service"); then
                die "Could not inspect $service. Check that systemd is running."
            fi
            [[ $state == loaded ]] || die "$service is not loaded (state: $state). Restore a configured unit first, or remove it from $services_file."
        done
    fi
fi

run() {
    if $dry_run; then
        printf 'Would run: '; printf '%q ' "$@"; printf '\n'
    else
        "$@"
    fi
}

if [[ -n ${seen[docker.service]:-} ]]; then
    run docker compose version
fi

for service in "${services[@]}"; do
    case "$service" in
        docker.service|tailscaled.service) run sudo systemctl enable --now "$service" ;;
        *) run sudo systemctl start "$service" ;;
    esac
    if ! $dry_run; then
        systemctl is-active --quiet "$service" || die "$service did not become active. Check its journal."
    fi
done

if $configure_git; then
    run git config --global --replace-all user.name "$git_name"
    run git config --global --replace-all user.email "$git_email"
fi

if ! $dry_run; then
    printf 'System service and Git configuration completed successfully.\n'
    if [[ -n ${seen[tailscaled.service]:-} ]]; then
        printf 'If this machine is not enrolled in Tailscale, run: sudo tailscale up\n'
    fi
fi
