#!/usr/bin/env sh
# Runs every pre-commit check: formatting, lint, types, unit tests.
set -e
cd "$(dirname "$0")/.."
stylua --check src tests scripts
selene src tests scripts
if command -v luau-lsp > /dev/null 2>&1; then
	./scripts/typecheck.sh
else
	echo "luau-lsp not installed, skipping type check (run: rokit install)"
fi
lune run tests/run
