#!/bin/bash
# Put the agentcron CLI on PATH. The bar widget works without this; the CLI is
# how you create and inspect jobs from a terminal.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/agentcron"

if [[ ${1:-} == --uninstall ]]; then
  if [[ -L $TARGET ]]; then
    rm -f "$TARGET"
    echo "removed $TARGET"
  else
    echo "nothing to remove at $TARGET"
  fi
  exit 0
fi

mkdir -p "$BIN_DIR"

if [[ -e $TARGET && ! -L $TARGET ]]; then
  echo "refusing to replace a real file at $TARGET" >&2
  exit 1
fi

ln -sfn "${PLUGIN_DIR}/bin/agentcron" "$TARGET"
echo "linked $TARGET -> ${PLUGIN_DIR}/bin/agentcron"

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) echo "warning: ${BIN_DIR} is not on your PATH" >&2 ;;
esac

"$TARGET" doctor || true
