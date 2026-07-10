#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTDIR="${DESTDIR:-}"
PREFIX="/usr/local"
CONFIG_DIR="/etc"
PROFILE_DIR="/etc/profile.d"
ZSH_PROFILE_DIR="/etc/zsh/zprofile.d"
ACTION=install

usage() {
    cat <<'EOF'
Usage: ./install.sh [--uninstall] [--prefix DIR] [--config-dir DIR]
                    [--profile-dir DIR] [--zsh-profile-dir DIR]

Copies ssh-status into the local system. It installs no packages and performs
no network operations. DESTDIR may be set for packaging or test installs.
EOF
}

while (($#)); do
    case "$1" in
        --uninstall) ACTION=uninstall ;;
        --prefix) PREFIX="${2:?--prefix requires a directory}"; shift ;;
        --config-dir) CONFIG_DIR="${2:?--config-dir requires a directory}"; shift ;;
        --profile-dir) PROFILE_DIR="${2:?--profile-dir requires a directory}"; shift ;;
        --zsh-profile-dir) ZSH_PROFILE_DIR="${2:?--zsh-profile-dir requires a directory}"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'install.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

target() { printf '%s%s' "$DESTDIR" "$1"; }

BIN_PATH="$(target "$PREFIX/bin/ssh-status")"
CONFIG_PATH="$(target "$CONFIG_DIR/ssh-status.conf")"
PROFILE_PATH="$(target "$PROFILE_DIR/20-ssh-status.sh")"
ZSH_PATH="$(target "$ZSH_PROFILE_DIR/20-ssh-status.zsh")"

if [[ "$ACTION" == uninstall ]]; then
    rm -f -- "$BIN_PATH" "$PROFILE_PATH" "$ZSH_PATH"
    printf 'Removed ssh-status program and login guards.\n'
    printf 'Configuration kept at %s (remove it manually if no longer needed).\n' "$CONFIG_PATH"
    exit 0
fi

mkdir -p -- "$(dirname "$BIN_PATH")" "$(dirname "$CONFIG_PATH")" "$(dirname "$PROFILE_PATH")"
install -m 0755 "$ROOT_DIR/src/ssh-status" "$BIN_PATH"
install -m 0644 "$ROOT_DIR/src/ssh-status-login.sh" "$PROFILE_PATH"

if [[ ! -e "$CONFIG_PATH" ]]; then
    install -m 0644 "$ROOT_DIR/config/config.example" "$CONFIG_PATH"
    printf 'Installed configuration: %s\n' "$CONFIG_PATH"
else
    printf 'Kept existing configuration: %s\n' "$CONFIG_PATH"
fi

if [[ -d "$(target "$ZSH_PROFILE_DIR")" ]]; then
    install -m 0644 "$ROOT_DIR/src/ssh-status-login.sh" "$ZSH_PATH"
    printf 'Installed zsh login guard: %s\n' "$ZSH_PATH"
fi

printf 'Installed program: %s\n' "$BIN_PATH"
printf 'Installed login guard: %s\n' "$PROFILE_PATH"
