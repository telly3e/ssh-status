#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$PASS" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1" >&2; }

assert_contains() {
    local output="$1" expected="$2" label="$3"
    if [[ "$output" == *"$expected"* ]]; then pass "$label"; else fail "$label (missing: $expected)"; fi
}

assert_not_contains() {
    local output="$1" unexpected="$2" label="$3"
    if [[ "$output" != *"$unexpected"* ]]; then pass "$label"; else fail "$label (found: $unexpected)"; fi
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/proc" "$TMP_DIR/root/etc/zsh/zprofile.d"

cat > "$TMP_DIR/proc/cpuinfo" <<'EOF'
processor : 0
physical id : 0
core id : 0
model name : Fixture CPU
processor : 1
physical id : 0
core id : 1
model name : Fixture CPU
EOF
printf '90061.00 0.00\n' > "$TMP_DIR/proc/uptime"
printf '0.21 0.17 0.14 1/100 1\n' > "$TMP_DIR/proc/loadavg"

cat > "$TMP_DIR/os-release" <<'EOF'
NAME="Ubuntu"
VERSION_ID="24.04"
ID=ubuntu
ID_LIKE=debian
EOF

cat > "$TMP_DIR/bin/ip" <<'EOF'
#!/usr/bin/env bash
printf '1.1.1.1 via 10.0.0.1 dev eth0 src 10.0.0.12 uid 1000\n'
EOF

cat > "$TMP_DIR/bin/free" <<'EOF'
#!/usr/bin/env bash
cat <<OUT
              total        used        free      shared  buff/cache   available
Mem:     8589934592  2684354560  1000000000           0           0  5905580032
Swap:    2147483648           0  2147483648
OUT
EOF

cat > "$TMP_DIR/bin/ps" <<'EOF'
#!/usr/bin/env bash
printf '  1 ? 00:00:01 init\n 20 ? 00:00:00 worker\n'
EOF

cat > "$TMP_DIR/bin/who" <<'EOF'
#!/usr/bin/env bash
printf 'admin pts/0 2026-07-10 14:00 (10.0.0.2)\n'
EOF

cat > "$TMP_DIR/bin/df" <<'EOF'
#!/usr/bin/env bash
cat <<OUT
Filesystem       1-blocks        Used   Available Capacity Mounted on
/dev/vda1      85899345920 19327352832 66571993088      23% /
/dev/vdb1     536870912000 236223201280 300647710720      44% /data
OUT
EOF

cat > "$TMP_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${SYSTEMD_MODE:-ok}" in
  ok) exit 0 ;;
  failed) printf 'nginx.service loaded failed failed nginx\n' ;;
  unavailable) exit 1 ;;
esac
EOF

cat > "$TMP_DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "${DOCKER_MODE:-ok}" in
  ok)
    printf 'web|running|Up 2 hours (healthy)\napi|running|Up 2 hours (unhealthy)\nold|exited|Exited (0) 1 hour ago\n'
    ;;
  denied) exit 1 ;;
esac
EOF

cat > "$TMP_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
case "${SUDO_MODE:-denied}" in
  docker)
    [[ "${1:-}" == -n ]] || exit 2
    shift
    DOCKER_MODE=ok "$@"
    ;;
  denied) exit 1 ;;
esac
EOF

chmod +x "$TMP_DIR/bin/"*

run_panel() {
    PATH="$TMP_DIR/bin:$PATH" \
    SSH_STATUS_PROC_ROOT="$TMP_DIR/proc" \
    SSH_STATUS_OS_RELEASE="$TMP_DIR/os-release" \
    SSH_STATUS_REBOOT_FILE="$TMP_DIR/reboot-required" \
    SSH_STATUS_COLUMNS=80 NO_COLOR=1 \
    bash "$ROOT_DIR/src/ssh-status" "$@"
}

output="$(SSH_STATUS_DOCKER=0 run_panel)"
assert_contains "$output" 'Fixture CPU (2C/2T)' 'renders CPU topology'
assert_contains "$output" 'IP: 10.0.0.12' 'renders primary IPv4'
assert_contains "$output" 'Load: 0.21 / 0.17 / 0.14' 'renders load averages'
assert_contains "$output" 'Memory: 2.5 GiB / 8.0 GiB (31%)' 'renders memory usage'
assert_contains "$output" '磁盘 /data' 'renders multiple real mount points'
assert_not_contains "$output" 'Docker' 'hides Docker when disabled or absent'
assert_contains "$output" 'systemd: OK' 'renders healthy systemd state'
assert_contains "$output" 'Reboot: no' 'renders Debian reboot state'

output="$(DOCKER_MODE=ok run_panel)"
assert_contains "$output" '3 containers: 2 running, 1 stopped' 'counts Docker containers'
assert_contains "$output" 'unhealthy: api' 'reports unhealthy containers'
assert_contains "$output" 'exited: old' 'reports exited containers'

output="$(DOCKER_MODE=denied run_panel)"
assert_contains "$output" '无法读取 Docker 状态' 'degrades when direct and sudo Docker queries fail'

output="$(DOCKER_MODE=denied SUDO_MODE=docker run_panel)"
assert_contains "$output" '3 containers: 2 running, 1 stopped' 'uses non-interactive sudo fallback for Docker'
assert_contains "$output" 'unhealthy: api' 'preserves Docker health details through sudo'

output="$(SYSTEMD_MODE=failed SSH_STATUS_DOCKER=0 run_panel)"
assert_contains "$output" 'systemd: nginx.service' 'reports failed systemd units'

output="$(SYSTEMD_MODE=unavailable SSH_STATUS_DOCKER=0 run_panel)"
assert_contains "$output" 'systemd: N/A' 'degrades when systemd is unavailable'

touch "$TMP_DIR/reboot-required"
output="$(SSH_STATUS_DOCKER=0 run_panel)"
assert_contains "$output" 'Reboot: 需要重启' 'reports required reboot'

cat > "$TMP_DIR/test.conf" <<'EOF'
theme=forest
docker=false
disk_exclude=/data
ascii=true
EOF
output="$(run_panel --config "$TMP_DIR/test.conf")"
assert_contains "$output" '+-' 'honors ASCII mode from configuration'
assert_not_contains "$output" '磁盘 /data' 'honors configured disk exclusions'
assert_not_contains "$output" 'Docker' 'honors configured Docker switch'

guard_output="$(SSH_TTY=/dev/pts/0 bash "$ROOT_DIR/src/ssh-status-login.sh")"
if [[ -z "$guard_output" ]]; then pass 'login guard is silent in non-interactive shells'; else fail 'login guard wrote to non-interactive shell'; fi

DESTDIR="$TMP_DIR/root" bash "$ROOT_DIR/install.sh" >/dev/null
if [[ -x "$TMP_DIR/root/usr/local/bin/ssh-status" && -f "$TMP_DIR/root/etc/profile.d/20-ssh-status.sh" && -f "$TMP_DIR/root/etc/ssh-status.conf" && -f "$TMP_DIR/root/etc/zsh/zprofile.d/20-ssh-status.zsh" ]]; then
    pass 'installer copies program, config, and guarded profile files'
else
    fail 'installer output is incomplete'
fi

DESTDIR="$TMP_DIR/root" bash "$ROOT_DIR/install.sh" --uninstall >/dev/null
if [[ ! -e "$TMP_DIR/root/usr/local/bin/ssh-status" && -f "$TMP_DIR/root/etc/ssh-status.conf" ]]; then
    pass 'uninstaller removes code and preserves configuration'
else
    fail 'uninstaller did not preserve the expected state'
fi

if ((FAIL > 0)); then
    printf '%d smoke test(s) failed\n' "$FAIL" >&2
    exit 1
fi
printf 'All %d smoke tests passed.\n' "$PASS"
