# CachyOS restore

Run the restore as your normal user on CachyOS:

```bash
./restore.sh --dry-run
./restore.sh
```

The script installs the packages in [packages/system.txt](packages/system.txt)
using `sudo pacman -Syu --needed`. It refreshes the package databases and
upgrades the system in the same transaction. It then restores dotfiles with
chezmoi and configures services and Git. Edit the package list, or supply a
replacement with `--packages-file PATH`. Repository availability depends on your
CachyOS configuration; pacman reports unavailable packages and stops.
The package step always installs Zsh, including with a replacement package list,
and sets it as the current user's login shell. New login sessions use Zsh;
`--skip-packages` also skips this shell change.
The package step also installs `xdg-user-dirs`. During configuration, the restore
enables `~/Projects` as the Projects user directory if none is configured;
an existing custom Projects location is preserved. `--skip-config` skips this.

The list includes CachyOS's `brave-origin-bin` and the native Arch `zed` package,
Docker and Compose, Tailscale, cloudflared, and the CLI tools and runtimes. Zed
and Brave are installed as native packages. PyPy tracks the version provided by
CachyOS/Arch. When an NVIDIA GPU is detected, the package step uses CachyOS
`chwd` to install the closed-source `nvidia-dkms-580xx` profile (the PRIME
variant on laptops). The profile must support the GPU; chwd reports an error if
it does not. The driver may conflict with an existing NVIDIA profile and may
require package confirmation. Reboot after installation. Use `--skip-nvidia`
to leave drivers alone; `--skip-packages` skips this step as well.

## Proton Pass and dotfiles

The package step installs Proton Pass CLI (`pass-cli`) with [Proton’s official
installer](https://protonpass.github.io/pass-cli/get-started/installation/) when
it is missing. It downloads the installer over HTTPS and installs the CLI to
`~/.local/bin`. Existing installations on PATH are left in place. If you use
`--skip-packages`, make sure the CLI is already installed before restoring dotfiles.

The script logs in to Proton Pass if necessary, reads the age identity, validates
it, and uses `chezmoi init --apply`. It will not replace a different existing
identity unless `--replace-key` is supplied. Supported overrides are `REPO_URL`,
`PROTON_PASS_AGE_KEY_REF`, `PROTON_PASS_VAULT`, `PROTON_PASS_AGE_KEY_ITEM`,
`PROTON_PASS_AGE_KEY_FIELD`, and `XDG_CONFIG_HOME`; see
`./scripts/restore-dotfiles.sh --help`.

## Services and options

The default [service list](config/services.txt) enables and starts Docker and
Tailscale, and starts an existing configured cloudflared service. Configure the
cloudflared unit and credentials first, or edit the service list. Git identity
can be set with `--git-name` and `--git-email` or the `RESTORE_GIT_NAME` and
`RESTORE_GIT_EMAIL` environment variables. Run `./restore.sh --help` for all
options, including skipping packages, dotfiles, services, or Git. The restore
stops on error and does not roll back completed changes.

Run tests with `python -m unittest discover -s tests`.
