#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
	printf 'Usage: %s <eval-repo> <eval-runtime> <spec-runtime> <target-checkout> <output-dir>\n' "$0" >&2
	exit 2
fi

EVAL_REPO="$(cd "$1" && pwd -P)"
EVAL_RUNTIME="$2"
SPEC_RUNTIME="$3"
SPEC_TARGET_ROOT="$(cd "$4" && pwd -P)"
OUTPUT_DIR="$5"
SPEC_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
CONFIG="$SPEC_ROOT/evaluation/hardening-v1.0.1/eval.json"

mkdir -p "$OUTPUT_DIR"
(
	cd "$EVAL_REPO"
	env \
		SPEC_ROOT="$SPEC_ROOT" \
		SPEC_TARGET_ROOT="$SPEC_TARGET_ROOT" \
		KUJO_BIN="$SPEC_RUNTIME" \
		"$EVAL_RUNTIME" run main.kujo run "$CONFIG" \
			--output-dir "$OUTPUT_DIR" \
			--artifact-checksums \
			--no-color
	"$EVAL_RUNTIME" run main.kujo verify-manifest --output-dir "$OUTPUT_DIR" --json
)
