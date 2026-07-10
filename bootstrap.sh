#!/usr/bin/env bash

# Network bootstrap for ssh-status. It downloads a GitHub source archive and
# delegates all system changes to the repository's install.sh.

set -euo pipefail

REPOSITORY="${SSH_STATUS_REPOSITORY:-telly3e/ssh-status}"
REF="${SSH_STATUS_REF:-main}"
ARCHIVE_FILE="${SSH_STATUS_ARCHIVE_FILE:-}"
ARCHIVE_URL="${SSH_STATUS_ARCHIVE_URL:-https://github.com/${REPOSITORY}/archive/refs/heads/${REF}.tar.gz}"

log() { printf 'ssh-status bootstrap: %s\n' "$*"; }
die() { printf 'ssh-status bootstrap: %s\n' "$*" >&2; exit 1; }

[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 'invalid SSH_STATUS_REPOSITORY value'
[[ "$REF" =~ ^[A-Za-z0-9._/-]+$ && "$REF" != *..* ]] || die 'invalid SSH_STATUS_REF value'
command -v tar >/dev/null 2>&1 || die 'tar is required'
command -v mktemp >/dev/null 2>&1 || die 'mktemp is required'

if ((EUID != 0)) && [[ -z "${DESTDIR:-}" ]]; then
    die 'run this installer as root, for example: curl ... | sudo bash'
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT INT TERM
ARCHIVE_PATH="$TMP_DIR/ssh-status.tar.gz"

if [[ -n "$ARCHIVE_FILE" ]]; then
    [[ -r "$ARCHIVE_FILE" ]] || die "cannot read archive: $ARCHIVE_FILE"
    cp -- "$ARCHIVE_FILE" "$ARCHIVE_PATH"
else
    log "downloading ${REPOSITORY}@${REF}"
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 --retry 3 --fail --silent --show-error --location \
            "$ARCHIVE_URL" --output "$ARCHIVE_PATH"
    elif command -v wget >/dev/null 2>&1; then
        wget --https-only --quiet --output-document="$ARCHIVE_PATH" "$ARCHIVE_URL"
    else
        die 'curl or wget is required'
    fi
fi

tar -tzf "$ARCHIVE_PATH" >/dev/null 2>&1 || die 'downloaded file is not a valid gzip tar archive'
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

SOURCE_DIR=''
for candidate in "$TMP_DIR"/*; do
    if [[ -d "$candidate" && -f "$candidate/install.sh" && -f "$candidate/src/ssh-status" ]]; then
        SOURCE_DIR="$candidate"
        break
    fi
done
[[ -n "$SOURCE_DIR" ]] || die 'archive does not contain the expected ssh-status project files'

log "installing ${REPOSITORY}@${REF}"
bash "$SOURCE_DIR/install.sh" "$@"
log 'complete'
