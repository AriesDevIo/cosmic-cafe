#!/usr/bin/env sh
# Strict Luau type check of src/ with luau-lsp + Roblox type definitions.
set -e
cd "$(dirname "$0")/.."
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cosmic-cafe"
DEFS="$CACHE/globalTypes.d.luau"
mkdir -p "$CACHE"
if [ ! -f "$DEFS" ]; then
	curl -sSfL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json > /dev/null
OUTPUT=$(luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json src 2>&1 | grep -E "^/|Error" || true)
if [ -n "$OUTPUT" ]; then
	echo "$OUTPUT" | sed 's/ \[game[^]]*\]//' | sort -u
	exit 1
fi
echo "typecheck: no errors"
