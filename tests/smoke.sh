#!/usr/bin/env bash
# Non-destructive smoke tests. Run from anywhere:
#   ./tests/smoke.sh
set -uo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CLI="$ROOT/bin/void"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export VOID_SV_DIR="$TMP/etc/sv"
export VOID_SERVICE_DIR="$TMP/var/service"
export VOID_LOG_DIR="$TMP/var/log"
export VOID_XBPS_CONF_DIR="$TMP/etc/xbps.d"
mkdir -p "$VOID_SV_DIR" "$VOID_SERVICE_DIR" "$VOID_LOG_DIR" "$VOID_XBPS_CONF_DIR"

failures=0

check() {
    local name=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name" >&2
        failures=$((failures + 1))
    fi
}

check_fails() {
    local name=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'FAIL %s (expected a non-zero exit)\n' "$name" >&2
        failures=$((failures + 1))
    else
        printf 'ok   %s\n' "$name"
    fi
}

check "version" "$CLI" --version
check "help" "$CLI" --no-color help
check "pkg help" "$CLI" --no-color pkg help
check "svc help" "$CLI" --no-color svc help
check "info" "$CLI" --no-color info
check "cheat" "$CLI" --no-color cheat
check "cheat filter" "$CLI" --no-color cheat systemctl
check "repo list" "$CLI" --no-color repo list
check "pkg repo list" "$CLI" --no-color pkg repo list
check "pkg repo available" "$CLI" --no-color pkg repo available
check "pkg repo available filter" "$CLI" --no-color pkg repo available hyprland
check "pkg repo info blackhole" "$CLI" --no-color pkg repo info blackhole
check "pkg repo help" "$CLI" --no-color pkg repo help
check "dry-run pkg repo add blackhole" "$CLI" --no-color --dry-run pkg repo add blackhole
check "dry-run pkg repo add vup-browsers" "$CLI" --no-color --dry-run pkg repo add vup-browsers
check "dry-run pkg repo add url" "$CLI" --no-color --dry-run pkg repo add https://repo.example.org/void --name example
check_fails "pkg repo add unknown" "$CLI" --no-color --dry-run pkg repo add not-a-real-repo
check_fails "pkg repo add bad url" "$CLI" --no-color --dry-run pkg repo add ftp://example.org/x

# Repository conflicts: BlackHole, its Russian mirror, and the standalone
# Hyprland repo all publish the same Hyprland packages, so only one may be
# enabled at a time.
cat >"$VOID_XBPS_CONF_DIR/20-blackhole.conf" <<'CONF'
repository=https://mirror.black-hole.dev/x86_64/
CONF
check "repo info lists conflicts" bash -c \
    "'$CLI' --no-color pkg repo info blackhole | grep -q 'Conflicts with'"
check "repo info flags an enabled conflict" bash -c \
    "'$CLI' --no-color pkg repo info hyprland | grep -q 'Enabled now.*blackhole'"
check_fails "pkg repo add conflicting" "$CLI" --no-color --dry-run pkg repo add hyprland
check_fails "pkg repo add conflicting mirror" "$CLI" --no-color --dry-run pkg repo add blackhole-ru
check "conflict check leaves the config alone" test -e "$VOID_XBPS_CONF_DIR/20-blackhole.conf"
check "pkg repo remove blackhole resolves by url" bash -c \
    "'$CLI' --no-color --dry-run pkg repo remove blackhole | grep -q '20-blackhole.conf'"
rm -f "$VOID_XBPS_CONF_DIR/20-blackhole.conf"

check "desktop help" "$CLI" --no-color desktop help
check "dry-run desktop refresh" "$CLI" --no-color --dry-run desktop refresh
check "dry-run desktop refresh user" "$CLI" --no-color --dry-run desktop refresh --user --no-icons --no-mime
check "pkg search" "$CLI" --no-color pkg search dbus
check "pkg list manual" "$CLI" --no-color pkg list --manual
check "pkg info" "$CLI" --no-color pkg info dbus
check "pkg files" "$CLI" --no-color pkg files dbus
check "dry-run install" "$CLI" --no-color --dry-run pkg install neovim
check "dry-run upgrade" "$CLI" --no-color --dry-run pkg upgrade
check "dry-run install --jobs" "$CLI" --no-color --dry-run pkg install neovim --jobs 4
check "dry-run install -j inline" "$CLI" --no-color --dry-run pkg install neovim -j8
check "dry-run install --no-parallel" "$CLI" --no-color --dry-run pkg install neovim --no-parallel
check "dry-run upgrade --jobs" "$CLI" --no-color --dry-run pkg upgrade --jobs 3
check "pkg help mentions jobs" bash -c "'$CLI' --no-color pkg help | grep -q -- '--jobs'"
check "dry-run create" "$CLI" --no-color --dry-run svc create smoke-test --exec "sleep 1" --enable

if (( failures > 0 )); then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
fi
printf '\nAll smoke tests passed.\n'
