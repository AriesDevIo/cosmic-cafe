#!/usr/bin/env sh
# Runs every pre-commit check: formatting, lint, unit tests.
set -e
cd "$(dirname "$0")/.."
stylua --check src tests scripts
selene src tests scripts
lune run tests/run
