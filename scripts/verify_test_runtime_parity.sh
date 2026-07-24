#!/usr/bin/env bash
# Runtime parity verification for Spec.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tests/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
KUJO_BIN="${KUJO_BIN:-kujo}"
PASS=0; FAIL=0

echo "=== Runtime Parity Check ==="

check "validate module" bash -c "
	out=\"\$('$KUJO_BIN' run src/validate.kujo --json fixtures/valid_minimal.json 2>&1)\"
	echo \"\$out\" | python3 -c \"import sys,json; lines=[line for line in sys.stdin.read().splitlines() if line.strip().startswith('{')]; d=json.loads(lines[-1]); assert d['valid']==True\"
"

check "render module" bash -c "
	out=\"\$('$KUJO_BIN' run src/render.kujo --json fixtures/valid_minimal.json 2>&1)\"
	echo \"\$out\" | grep -q '# Spec:'
"

check "export module" bash -c "
	out=\"\$('$KUJO_BIN' run src/export.kujo --json fixtures/valid_minimal.json 2>&1)\"
	echo \"\$out\" | grep -q '## Task:'
"

report_results "Runtime Parity"
