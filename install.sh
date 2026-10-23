#!/usr/bin/env bash
set -euo pipefail

BIN_PREFIX="${AI_UPGRADER_PREFIX:-$HOME/.local/bin}"
DATA_HOME="${AI_UPGRADER_HOME:-$HOME/.local/share/ai-upgrader}"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -f "$HERE/ai-upgrader" ] || { echo "ERROR: missing ai-upgrader next to install.sh" >&2; exit 1; }
[ -f "$HERE/skills/universal-upgrade.md" ] || { echo "ERROR: missing universal skill" >&2; exit 1; }

mkdir -p "$BIN_PREFIX" "$DATA_HOME/skills"
rm -f "$BIN_PREFIX/ai-upgrader"
install -m 0755 "$HERE/ai-upgrader" "$BIN_PREFIX/ai-upgrader"
install -m 0644 "$HERE/skills/universal-upgrade.md" "$DATA_HOME/skills/universal-upgrade.md"
install -m 0644 "$HERE/POLICY.md" "$DATA_HOME/POLICY.md"
install -m 0644 "$HERE/GRACEFUL-STOP-CONTRACT.md" "$DATA_HOME/GRACEFUL-STOP-CONTRACT.md"
install -m 0644 "$HERE/README.md" "$DATA_HOME/README.md"
if [ -f "$HERE/MATRIX-SCHEMA.md" ]; then
  install -m 0644 "$HERE/MATRIX-SCHEMA.md" "$DATA_HOME/MATRIX-SCHEMA.md"
fi

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-upgrader"
mkdir -p "$CONF_DIR"
install -m 0755 "$HERE/watch.sh" "$BIN_PREFIX/ai-upgrader-watch"
install -m 0644 "$HERE/watch.env.example" "$CONF_DIR/watch.env.example"

echo "Installed executable: $BIN_PREFIX/ai-upgrader"
echo "Installed watcher:    $BIN_PREFIX/ai-upgrader-watch (setup: cp $CONF_DIR/watch.env.example $CONF_DIR/watch.env, fill it)"
echo "Installed skill:      $DATA_HOME/skills/universal-upgrade.md"
case ":$PATH:" in
  *":$BIN_PREFIX:"*) ;;
  *) echo "Add $BIN_PREFIX to PATH if it is not already there." ;;
esac

echo "Next: cd <project> && ai-upgrader upgrade"
