#!/usr/bin/env bash
# Shared test helpers for Spec verification scripts.
# Source this file in any test/verification script:
#   source "$(dirname "$0")/test_helpers.sh"
#
# Requires global variables: PASS, FAIL

check() {
	local desc="$1"; shift
	if "$@" > /dev/null 2>&1; then
		echo "  PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $desc"
		FAIL=$((FAIL + 1))
	fi
}

check_output() {
	local desc="$1" expected="$2"; shift 2
	local out; out="$("$@" 2>&1)" || true
	if echo "$out" | grep -q "$expected"; then
		echo "  PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $desc (expected: '$expected')"
		echo "    got: $(echo "$out" | head -1)"
		FAIL=$((FAIL + 1))
	fi
}

check_fail() {
	local desc="$1"; shift
	if ! "$@" > /dev/null 2>&1; then
		echo "  PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $desc (expected failure but succeeded)"
		FAIL=$((FAIL + 1))
	fi
}

report_results() {
	local label="${1:-Results}"
	echo ""
	echo "=== $label: $PASS passed, $FAIL failed ==="
	if [[ $FAIL -gt 0 ]]; then exit 1; fi
}
