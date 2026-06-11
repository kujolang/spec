#!/usr/bin/env bash
# Release quality gates for Spec.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tests/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
PASS=0
FAIL=0
SPEC_BENCH_COUNT="${SPEC_BENCH_COUNT:-30}"
SPEC_BENCH_BASELINE_SECONDS="${SPEC_BENCH_BASELINE_SECONDS:-60}"
SPEC_BENCH_PROFILE="${SPEC_BENCH_PROFILE:-ci-linux}"
SPEC_FUZZ_ITERATIONS="${SPEC_FUZZ_ITERATIONS:-100}"

echo "=== Spec Release Quality Gates ==="
echo ""

# Gate 1: Test suite passes
echo "[GATE 1] Test suite"
if bash "$PROJECT_DIR/tests/run_tests.sh" >/dev/null 2>&1; then echo "  PASS: Test suite"; PASS=$((PASS+1)); else echo "  FAIL: Test suite"; FAIL=$((FAIL+1)); fi
echo ""

# Gate 2: All source files exist
echo "[GATE 2] Source files"
check "validate.kujo exists" test -f src/validate.kujo
check "render.kujo exists" test -f src/render.kujo
check "export.kujo exists" test -f src/export.kujo
check "CLI script exists" test -f scripts/spec
check "CLI is executable" test -x scripts/spec
echo ""

# Gate 3: Schema exists and is valid JSON
echo "[GATE 3] Schema"
check "schema file exists" test -f schema/spec.schema.json
check "schema is valid JSON" python3 -c "import json; json.load(open('schema/spec.schema.json'))"
echo ""

# Gate 4: No secrets in source
echo "[GATE 4] Security scan"
check "no hardcoded secrets" bash -c "! grep -rq 'sk-[A-Za-z0-9]\{20,\}' src/ tests/ scripts/ 2>/dev/null"
echo ""

# Gate 5: README exists
echo "[GATE 5] Documentation"
check "README exists" test -f README.md
check "VERSION exists" test -f VERSION
echo ""

# Gate 6: kennel.toml is valid
echo "[GATE 6] Package metadata"
check "kennel.toml exists" test -f kennel.toml
echo ""

# Gate 7: Fixtures exist
echo "[GATE 7] Fixtures"
check "valid minimal fixture" test -f fixtures/valid_minimal.json
check "invalid missing goal fixture" test -f fixtures/invalid_missing_goal.yml
check "examples exist" test -f examples/basic.spec.yml
echo ""

# Gate 8: CLI commands work
echo "[GATE 8] CLI smoke test"
check "spec version works" bash -c "'$PROJECT_DIR/scripts/spec' version >/dev/null"
check "spec help works" bash -c "'$PROJECT_DIR/scripts/spec' help >/dev/null"
echo ""

# Gate 9: Benchmark health and trend guard
echo "[GATE 9] Benchmark + Trend Guard"
check "benchmark within budget (${SPEC_BENCH_PROFILE}: ${SPEC_BENCH_COUNT} specs <= ${SPEC_BENCH_BASELINE_SECONDS}s; trend guard enforced)" \
	bash -c "'$PROJECT_DIR/tests/benchmark.sh' '$SPEC_BENCH_COUNT' '$SPEC_BENCH_BASELINE_SECONDS' '$SPEC_BENCH_PROFILE' >/dev/null"
echo ""

# Gate 10: Fuzz health
echo "[GATE 10] Fuzz"
check "fuzz harness completes (${SPEC_FUZZ_ITERATIONS} iterations)" \
	bash -c "'$PROJECT_DIR/tests/fuzz.sh' '$SPEC_FUZZ_ITERATIONS' >/dev/null"
echo ""

# Gate 11: Completion parity
echo "[GATE 11] Shell Completions"
check "completion files match key command/flag surface" \
	bash -c "'$PROJECT_DIR/scripts/verify_completion_parity.sh' >/dev/null"
echo ""

report_results "Results"
