#!/usr/bin/env bash
# Verify all README commands are executable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tests/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$PROJECT_DIR/scripts/spec"
TMPDIR="$(mktemp -d "$PROJECT_DIR/.doc_parity_tmp.XXXXXX")"
trap "rm -rf $TMPDIR" EXIT

echo "=== Doc Command Parity Check ==="
PASS=0; FAIL=0

check "spec version" "$SPEC" version
check "spec help" "$SPEC" help
check "spec init" bash -c "'$SPEC' init --name test --output '$TMPDIR/t.yml'"
check "spec create alias" bash -c "'$SPEC' create --name alias-test --output '$TMPDIR/create.yml'"
check "spec validate" "$SPEC" validate "$PROJECT_DIR/fixtures/valid_minimal.json"
check "spec render" bash -c "'$SPEC' render '$PROJECT_DIR/fixtures/valid_minimal.json' >/dev/null"
check "spec export-agent-context" bash -c "'$SPEC' export-agent-context '$PROJECT_DIR/fixtures/valid_minimal.json' >/dev/null"
check "spec export" bash -c "'$SPEC' export '$PROJECT_DIR/fixtures/valid_minimal.json' --format agent >/dev/null"
check "spec export envelope" bash -c "'$SPEC' export '$PROJECT_DIR/fixtures/valid_minimal.json' --format envelope | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"metadata\" in d and \"payload\" in d'"
check "spec info" bash -c "'$SPEC' info '$PROJECT_DIR/fixtures/valid_minimal.json' >/dev/null"
check "spec list --json" bash -c "'$SPEC' list '$PROJECT_DIR/examples' --json | python3 -c 'import json,sys; json.load(sys.stdin)'"
check "spec validate-all" bash -c "'$SPEC' validate-all '$PROJECT_DIR/examples' | grep -q 'passed'"
check "spec search" bash -c "'$SPEC' search --priority high | grep -q 'high'"
check "spec status" bash -c "'$SPEC' status '$TMPDIR/t.yml' | grep -q 'draft'"
check "spec status --set" bash -c "python3 -c 'import json; json.dump({\"name\":\"status-test\",\"goal\":\"valid goal\",\"status\":\"draft\"}, open(\"$TMPDIR/status.json\",\"w\"))' && '$SPEC' status '$TMPDIR/status.json' --set review >/dev/null && '$SPEC' status '$TMPDIR/status.json' | grep -q 'review'"
check "spec convert" bash -c "'$SPEC' convert '$PROJECT_DIR/fixtures/valid_minimal.yml' --to json --output '$TMPDIR/conv.json' >/dev/null && python3 -c 'import json; json.load(open(\"$TMPDIR/conv.json\"))'"
check "spec template list" bash -c "'$SPEC' template list >/dev/null"
check "spec diff" bash -c "'$SPEC' diff '$PROJECT_DIR/fixtures/valid_minimal.json' '$PROJECT_DIR/fixtures/valid_minimal.yml' >/dev/null"
check "spec export-eval" bash -c "'$SPEC' export-eval '$PROJECT_DIR/fixtures/valid_minimal.json' --output '$TMPDIR/eval.json' >/dev/null && python3 -c 'import json; json.load(open(\"$TMPDIR/eval.json\"))'"
check "spec ci" bash -c "'$SPEC' ci '$PROJECT_DIR/examples' | grep -q 'passed'"
check "spec ci --format json" bash -c "'$SPEC' ci '$PROJECT_DIR/examples' --format json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"failed\"] == 0'"
check "spec ci --format github" bash -c "'$SPEC' ci '$PROJECT_DIR/examples' --format github | grep -q '::notice::Spec CI:'"
check "spec ci option-first ordering" bash -c "'$SPEC' ci --format json '$PROJECT_DIR/examples' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"failed\"] == 0'"
check "spec ci --max-files" bash -c "'$SPEC' ci '$PROJECT_DIR/examples' --format json --max-files 1 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"total\"] == 1 and d.get(\"truncated\") is True'"
check "spec ci --jobs" bash -c "'$SPEC' ci '$PROJECT_DIR/examples' --format json --jobs 2 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"failed\"] == 0 and d[\"total\"] >= 1'"
check "spec doctor" bash -c "'$SPEC' doctor | grep -q 'Spec Doctor'"
check "spec changelog" bash -c "ref=\$(git rev-parse --verify HEAD~1 2>/dev/null || git rev-parse --verify HEAD); '$SPEC' changelog \"\$ref\" >/dev/null"
check "spec graph mermaid" bash -c "'$SPEC' graph '$PROJECT_DIR/examples' --format mermaid | grep -q 'graph TD'"
check "spec graph dot" bash -c "'$SPEC' graph '$PROJECT_DIR/examples' --format dot | grep -q 'digraph Specs'"
check "completion parity script" bash -c "'$PROJECT_DIR/scripts/verify_completion_parity.sh' >/dev/null"
check "generated command inventory is current" bash -c "'$PROJECT_DIR/scripts/generate_command_inventory.sh' --check >/dev/null"

report_results "Doc Command Parity"
