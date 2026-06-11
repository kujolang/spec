#!/usr/bin/env bash
# Supply-chain policy check for Spec.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tests/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
PASS=0; FAIL=0

echo "=== Spec Supply-Chain Policy Check ==="
echo ""

check "No root scratch .kujo files" bash -c 'test -z "$(find . -maxdepth 1 -name test_*.kujo -print 2>/dev/null)"'
check "No node_modules" bash -c '! test -d node_modules'
check "No hardcoded secrets" bash -c '! grep -rq "sk-[A-Za-z0-9]\{20,\}" src/ tests/ scripts/ 2>/dev/null'
check "VERSION file present" test -f VERSION
check ".gitignore present" test -f .gitignore
check "kennel.toml present" test -f kennel.toml
check "kujo.toml present" test -f kujo.toml
check "README present" test -f README.md
check "Schema present" test -f schema/spec.schema.json
check "CLI script present" test -f scripts/spec

echo ""
report_results "Results"
