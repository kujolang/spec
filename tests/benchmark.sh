#!/usr/bin/env bash
# Spec Performance Benchmark — creates N specs and times validation.
# Usage: bash tests/benchmark.sh [count] [baseline_seconds] [profile]
set -euo pipefail

PROFILE="${3:-${SPEC_BENCH_PROFILE:-local}}"

default_count_for_profile() {
	case "$1" in
		ci-linux|ci-macos) echo "30" ;;
		stress) echo "300" ;;
		*) echo "100" ;;
	esac
}

default_baseline_for_profile() {
	case "$1" in
		ci-linux) echo "60" ;;
		ci-macos) echo "90" ;;
		stress) echo "120" ;;
		*) echo "30" ;;
	esac
}

default_runtime_budget_ms_for_profile() {
	case "$1" in
		ci-linux) echo "60000" ;;
		ci-macos) echo "90000" ;;
		stress) echo "120000" ;;
		*) echo "30000" ;;
	esac
}

COUNT="${1:-$(default_count_for_profile "$PROFILE")}" 
BASELINE="${2:-$(default_baseline_for_profile "$PROFILE")}" 
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$PROJECT_DIR/scripts/spec"
BENCH_DIR="$PROJECT_DIR/_benchmark_specs"
SPEC_BENCH_SUMMARY_FILE="${SPEC_BENCH_SUMMARY_FILE:-$PROJECT_DIR/tests/artifacts/benchmark_summary.json}"
SPEC_BENCH_TREND_BUDGET_FILE="${SPEC_BENCH_TREND_BUDGET_FILE:-$PROJECT_DIR/tests/benchmark_trend_budgets.json}"
rm -rf "$BENCH_DIR" 2>/dev/null || true
mkdir -p "$BENCH_DIR"
PASS=0
FAIL=0

cleanup() { rm -rf "$BENCH_DIR"; }
trap cleanup EXIT

echo "=== Spec Benchmark ==="
echo "Profile: $PROFILE"
echo "Method: generate N JSON specs, then time a single 'spec validate-all' pass"
echo "Creating $COUNT spec files..."

# Create N JSON spec files with varying content
for i in $(seq 1 "$COUNT"); do
	"$SPEC" init --name "benchmark-spec-$i" --format json --output "$BENCH_DIR/spec_$i.spec.json" > /dev/null 2>&1 || true
	# Set a non-empty goal so validation passes
	python3 -c "
import json
f = '$BENCH_DIR/spec_$i.spec.json'
try:
	d = json.load(open(f))
	d['goal'] = 'Benchmark spec $i'
	json.dump(d, open(f, 'w'), indent=2)
except: pass
" 2>/dev/null || true
done

echo "Validating $COUNT specs..."
START_TIME=$(python3 -c "import time; print(time.time())")

set +e
VALIDATE_OUTPUT="$("$SPEC" validate-all "$BENCH_DIR" 2>&1)"
VALIDATE_RC=$?
set -e
validated="$(echo "$VALIDATE_OUTPUT" | python3 -c "import re,sys; t=sys.stdin.read(); m=re.search(r'validate --all: (\\d+) passed, (\\d+) failed', t); print(m.group(1) if m else 0)")"
failed_count="$(echo "$VALIDATE_OUTPUT" | python3 -c "import re,sys; t=sys.stdin.read(); m=re.search(r'validate --all: (\\d+) passed, (\\d+) failed', t); print(m.group(2) if m else -1)")"

END_TIME=$(python3 -c "import time; print(time.time())")
ELAPSED=$(python3 -c "print(round($END_TIME - $START_TIME, 2))")
PER_SPEC=$(python3 -c "print(round($ELAPSED / $COUNT * 1000, 1))")
CI_RUNTIME_MS=$(python3 -c "print(int(round($ELAPSED * 1000)))")

TREND_BUDGET_MS="$(default_runtime_budget_ms_for_profile "$PROFILE")"
if [[ -f "$SPEC_BENCH_TREND_BUDGET_FILE" ]]; then
	file_budget="$(python3 -c '
import json, sys
try:
	d = json.load(open(sys.argv[1]))
	print(int(d.get(sys.argv[2], 0)))
except Exception:
	print(0)
' "$SPEC_BENCH_TREND_BUDGET_FILE" "$PROFILE" 2>/dev/null || echo 0)"
	if [[ "$file_budget" =~ ^[0-9]+$ ]] && [[ "$file_budget" -gt 0 ]]; then
		TREND_BUDGET_MS="$file_budget"
	fi
fi

echo ""
echo "=== Results ==="
echo "Specs created:  $COUNT"
echo "Specs validated: $validated/$COUNT"
echo "Total time:     ${ELAPSED}s"
echo "Per spec:       ${PER_SPEC}ms"
echo "CI runtime:     ${CI_RUNTIME_MS}ms"
echo "Trend budget:   ${TREND_BUDGET_MS}ms"
echo "Baseline max:   ${BASELINE}s"

mkdir -p "$(dirname "$SPEC_BENCH_SUMMARY_FILE")" 2>/dev/null || true
python3 -c '
import json, sys
payload = {
	"profile": sys.argv[1],
	"count": int(sys.argv[2]),
	"baseline_seconds": float(sys.argv[3]),
	"elapsed_seconds": float(sys.argv[4]),
	"per_spec_ms": float(sys.argv[5]),
	"ci_runtime_ms": int(sys.argv[6]),
	"trend_budget_ms": int(sys.argv[7]),
	"validated": int(sys.argv[8]),
	"failed_count": int(sys.argv[9]),
	"validate_exit_code": int(sys.argv[10])
}
with open(sys.argv[11], "w") as fh:
	json.dump(payload, fh, indent=2)
	fh.write("\n")
' "$PROFILE" "$COUNT" "$BASELINE" "$ELAPSED" "$PER_SPEC" "$CI_RUNTIME_MS" "$TREND_BUDGET_MS" "$validated" "$failed_count" "$VALIDATE_RC" "$SPEC_BENCH_SUMMARY_FILE" 2>/dev/null || true
echo "Summary JSON:   $SPEC_BENCH_SUMMARY_FILE"

if python3 -c "exit(0 if $ELAPSED <= $BASELINE else 1)" 2>/dev/null; then
	echo "PASS: Benchmark within baseline (${ELAPSED}s <= ${BASELINE}s)"
else
	echo "FAIL: Benchmark exceeded baseline (${ELAPSED}s > ${BASELINE}s)"
	echo "Validation summary: $VALIDATE_OUTPUT"
	exit 1
fi

if python3 -c "exit(0 if $CI_RUNTIME_MS <= $TREND_BUDGET_MS else 1)" 2>/dev/null; then
	echo "PASS: Trend guard within profile budget (${CI_RUNTIME_MS}ms <= ${TREND_BUDGET_MS}ms)"
else
	echo "FAIL: Trend guard budget exceeded (${CI_RUNTIME_MS}ms > ${TREND_BUDGET_MS}ms)"
	exit 1
fi

if [[ "$VALIDATE_RC" -ne 0 || "$failed_count" -gt 0 || "$validated" -ne "$COUNT" ]]; then
	echo "FAIL: benchmark validation pass was incomplete"
	echo "Validation summary: $VALIDATE_OUTPUT"
	exit 1
fi
