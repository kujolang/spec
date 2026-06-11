#!/usr/bin/env bash
# Verify shell completion files include key commands and flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tests/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

BASH_COMPLETION="$PROJECT_DIR/completions/spec.bash"
ZSH_COMPLETION="$PROJECT_DIR/completions/spec.zsh"
FISH_COMPLETION="$PROJECT_DIR/completions/spec.fish"

REQUIRED_COMMANDS=(
	init create init-interactive validate render export export-agent-context info
	list validate-all search status convert template watch diff export-eval ci
	doctor changelog graph version help
)

REQUIRED_FLAGS=(
	--format --payload-format --output --name --from --to --set --priority --tag
	--query --quiet --json --strict --max-depth --dir --max-files --fail-fast
	--jobs --unsafe-write --strict-template-source
)

echo "=== Completion Parity Check ==="

check "bash completion exists" test -f "$BASH_COMPLETION"
check "zsh completion exists" test -f "$ZSH_COMPLETION"
check "fish completion exists" test -f "$FISH_COMPLETION"

for cmd in "${REQUIRED_COMMANDS[@]}"; do
	check "bash includes command: $cmd" bash -c "grep -q -- '$cmd' '$BASH_COMPLETION'"
	check "zsh includes command: $cmd" bash -c "grep -q -- '$cmd' '$ZSH_COMPLETION'"
	check "fish includes command: $cmd" bash -c "grep -q -- '$cmd' '$FISH_COMPLETION'"
done

for flag in "${REQUIRED_FLAGS[@]}"; do
	fish_flag="${flag#--}"
	check "bash includes flag: $flag" bash -c "grep -q -- '$flag' '$BASH_COMPLETION'"
	check "zsh includes flag: $flag" bash -c "grep -q -- '$flag' '$ZSH_COMPLETION'"
	check "fish includes flag: $flag" bash -c "grep -q -- '-l $fish_flag' '$FISH_COMPLETION'"
done

report_results "Completion Parity"
