#!/bin/sh
# Install the `void` command and its bash completion.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PREFIX=${PREFIX:-$HOME/.local}
DESTDIR=${DESTDIR:-}
BINDIR="$DESTDIR$PREFIX/bin"
COMPLETION_DIR="$DESTDIR$PREFIX/share/bash-completion/completions"
BIN="$BINDIR/void"
COMPLETION="$COMPLETION_DIR/void"

uninstall=0
if [ "${1:-}" = "--uninstall" ]; then
    uninstall=1
fi

if [ "$uninstall" -eq 1 ]; then
    rm -f "$BIN" "$COMPLETION"
    printf 'Removed %s\n' "$BIN"
    printf 'Removed %s\n' "$COMPLETION"
    exit 0
fi

if [ ! -f "$ROOT/bin/void" ]; then
    printf 'error: bin/void not found next to install.sh\n' >&2
    exit 1
fi

mkdir -p "$BINDIR" "$COMPLETION_DIR"
install -m 0755 "$ROOT/bin/void" "$BIN"
install -m 0644 "$ROOT/completions/void.bash" "$COMPLETION"

printf 'Installed %s\n' "$BIN"
printf 'Installed %s\n' "$COMPLETION"

case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *)
        printf '\nAdd this to your shell profile:\n'
        printf '  export PATH="%s:$PATH"\n' "$BINDIR"
        ;;
esac

printf '\nTry it:\n'
printf '  void info\n'
printf '  void pkg search neovim\n'
printf '  void svc list\n'
printf '  void cheat\n'
