#!/usr/bin/env bash
# Fuzz tests — feed random JSON to spec validate and verify no crashes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$PROJECT_DIR/scripts/spec"
ITERATIONS="${1:-200}"
PASS=0
FAIL=0

echo "=== Spec Fuzz Tests ($ITERATIONS iterations) ==="
echo ""

# Generate random JSON objects and validate them
for i in $(seq 1 "$ITERATIONS"); do
	(( i % 50 == 0 )) && echo "  Progress: $i/$ITERATIONS"

	# Generate random JSON using Python
	if ! python3 -c "
import json, random, string, sys
def rand_str(n):
	return ''.join(random.choice(string.ascii_letters + string.digits + ' _-') for _ in range(n))

spec = {}
# Sometimes include name, sometimes not
if random.random() > 0.2:
	spec['name'] = rand_str(random.randint(0, 300))
# Sometimes include goal, sometimes not
if random.random() > 0.2:
	spec['goal'] = rand_str(random.randint(0, 6000))
# Random priority
if random.random() > 0.5:
	spec['priority'] = random.choice(['critical', 'high', 'medium', 'low', 'invalid_priority'])
# Random version
if random.random() > 0.5:
	spec['version'] = rand_str(random.randint(0, 50))
# Random tags
if random.random() > 0.5:
	spec['tags'] = [rand_str(random.randint(1, 50)) for _ in range(random.randint(0, 20))]
# Random extra fields
if random.random() > 0.3:
	spec[rand_str(random.randint(1, 20))] = rand_str(random.randint(0, 200))

json.dump(spec, open('${PROJECT_DIR}/_fuzz_test.json', 'w'))
" 2>/dev/null; then
		echo "  FAIL: iteration $i — fixture generation failed"
		FAIL=$((FAIL + 1))
		continue
	fi

	# Validate — expected outcomes are rc=0 (valid) or rc=1 (validation failure).
	set +e
	out="$($SPEC validate "$PROJECT_DIR/_fuzz_test.json" 2>&1)"
	rc=$?
	set -e

	local_ok=true

	# Verify: exit code is 0 or 1 (never anything else).
	if [[ "$rc" != "0" ]] && [[ "$rc" != "1" ]]; then
		local_ok=false
		echo "  FAIL: iteration $i — unexpected exit code $rc"
		echo "    output: $(echo "$out" | head -3 | tr '\n' ' ')"
	fi

	# Verify output shape only for expected exit code paths.
	if $local_ok; then
		if [[ -n "$out" ]]; then
			if echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
				: # Valid JSON output
			elif echo "$out" | grep -q "PASS:\|FAIL:\|Error:" 2>/dev/null; then
				: # Human-readable output
			else
				local_ok=false
				echo "  FAIL: iteration $i — unrecognized output format"
				echo "    output: $(echo "$out" | head -3 | tr '\n' ' ')"
			fi
		fi
	fi

	if $local_ok; then
		PASS=$((PASS + 1))
	fi
	if ! $local_ok; then
		FAIL=$((FAIL + 1))
	fi
done

rm -f "$PROJECT_DIR/_fuzz_test.json"

echo ""
echo "Fuzz summary: PASS=$PASS FAIL=$FAIL ITERATIONS=$ITERATIONS"

report_results "Fuzz ($ITERATIONS iterations)"
