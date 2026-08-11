#!/usr/bin/env bash
# Spec test suite — validates all spec CLI commands work correctly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$PROJECT_DIR/scripts/spec"
TMPDIR="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "=== Spec Test Suite ==="
echo ""

# 1. Version
check_output "version prints version" "Spec" "$SPEC" version

# 1a. TEST-JSON: version --json output contract
check "version --json matches contract shape" bash -c "
	'$SPEC' version --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert set([\"version\",\"contract\",\"schema_version\"]).issubset(d.keys()); assert isinstance(d[\"version\"], str); assert isinstance(d[\"contract\"], str); assert isinstance(d[\"schema_version\"], str)'
"

# 2. Help
check_output "help prints usage" "Usage:" "$SPEC" help

# 3. Init YAML
check "init creates YAML spec" bash -c "
	'$SPEC' init --name test --output '$TMPDIR/test.yml' &&
	grep -q 'name: \"test\"' '$TMPDIR/test.yml'
"

# 4. Init JSON
check "init creates JSON spec" bash -c "
	'$SPEC' init --name test --format json --output '$TMPDIR/test.json' &&
	grep -q '\"name\"' '$TMPDIR/test.json'
"

# 4a. SEC-03: init rejects dangerous name with quotes
check_fail "init rejects name with quotes" "$SPEC" init --name "bad'; echo injected;'" --output "$TMPDIR/bad.yml"

# 4b. SEC-03: init rejects name with backticks
check_fail "init rejects name with backticks" "$SPEC" init --name 'bad`whoami`' --output "$TMPDIR/bad.yml"

# 4c. SEC-03: init accepts safe name with hyphens
check "init accepts name with hyphens" bash -c "
	'$SPEC' init --name 'my-feature-name' --output '$TMPDIR/safe.yml' &&
	grep -q 'my-feature-name' '$TMPDIR/safe.yml'
"

# 4d. SEC-11: init --from applies the same name sanitizer as normal init
check_fail "init --from rejects dangerous name with quotes" bash -c "
	printf '{\"name\":\"safe\",\"goal\":\"valid goal\"}' | '$SPEC' init --from - --name 'bad\"name' --output '${PROJECT_DIR}/_test_from_bad_name.yml' >/dev/null 2>&1
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_from_bad_name.yml'
	exit \$rc
"

# 4e. SEC-11: json import sources outside the project are rejected
check_fail "init --from json rejects outside-project source" bash -c "
	src='$TMPDIR/outside-source.json'
	printf '{\"name\":\"safe\",\"goal\":\"valid goal\"}' > \"\$src\"
	'$SPEC' init --from json:\"\$src\" --output '${PROJECT_DIR}/_test_outside_import.yml' >/dev/null 2>&1
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_outside_import.yml'
	exit \$rc
"

# 5. Validate valid spec
check "validate passes on valid JSON spec" "$SPEC" validate "$PROJECT_DIR/fixtures/valid_minimal.json"

# 5a. TEST-JSON: validate --json output contract
check "validate --json matches contract shape" bash -c "
	'$SPEC' validate '$PROJECT_DIR/fixtures/valid_minimal.json' --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"valid\" in d; assert isinstance(d[\"valid\"], bool); assert \"errors\" in d and isinstance(d[\"errors\"], list); assert \"warnings\" in d and isinstance(d[\"warnings\"], list); assert d[\"valid\"] is True'
"

# 6. Validate invalid spec (missing goal)
check_fail "validate fails on spec missing goal" "$SPEC" validate "$PROJECT_DIR/fixtures/invalid_missing_goal.yml"

# 7. Validate invalid spec (missing name)
check_fail "validate fails on spec missing name" "$SPEC" validate "$PROJECT_DIR/fixtures/invalid_missing_name.yml"

# 8. SEC-01: malicious filename with quotes does not cause injection
check_fail "validate safely rejects file with quotes in name" bash -c "
	badname=\"$TMPDIR/test'; import os; os.system('echo pwned');'.yml\"
	touch \"\$badname\" 2>/dev/null || true
	# Must not print 'pwned' — that would indicate code injection
	out=\"\$('$SPEC' validate \"\$badname\" 2>&1)\" || true
	! echo \"\$out\" | grep -q 'pwned'
"

# 9. SEC-01: malicious filename with semicolons does not cause injection
check_fail "validate safely rejects file with semicolons in name" bash -c "
	badname=\"$TMPDIR/test;echo injected;.yml\"
	touch \"\$badname\" 2>/dev/null || true
	out=\"\$('$SPEC' validate \"\$badname\" 2>&1)\" || true
	! echo \"\$out\" | grep -q 'injected'
"

# 10. SEC-02: path traversal with .. is rejected
check_fail "validate rejects path traversal (..)" bash -c "
	out=\"\$('$SPEC' validate '$TMPDIR/../etc/passwd' 2>&1)\" || true
	echo \"\$out\" | grep -q 'Path traversal'
"

# 11. SEC-02: absolute path outside project is rejected
check "validate rejects absolute path outside project" bash -c "
	'$SPEC' validate /etc/passwd 2>&1 | grep -q 'outside project'
"
# Also verify exit code is non-zero
check_fail "validate exits non-zero on outside-project path" "$SPEC" validate /etc/passwd

# 12. SEC-02: relative path within project is allowed
check "validate allows safe relative path" "$SPEC" validate "$PROJECT_DIR/fixtures/valid_minimal.json"

# 13. Render
check_output "render produces markdown" "# Spec:" "$SPEC" render "$PROJECT_DIR/fixtures/valid_minimal.json"

# 13a. SEC-08: safe-write blocks outputs outside project when enabled
check_fail "render blocks outside output path when safe-write is on" bash -c "
	SPEC_SAFE_WRITE=on '$SPEC' render '$PROJECT_DIR/fixtures/valid_minimal.json' --output '$TMPDIR/safe_write_block.md' >/dev/null 2>&1
"

# 13b. SEC-08: unsafe-write override bypasses safe-write boundary
check "render allows outside output path with --unsafe-write" bash -c "
	SPEC_SAFE_WRITE=on '$SPEC' render '$PROJECT_DIR/fixtures/valid_minimal.json' --output '$TMPDIR/safe_write_allow.md' --unsafe-write >/dev/null 2>&1
	rc=\$?
	[[ -f '$TMPDIR/safe_write_allow.md' ]] || rc=1
	rm -f '$TMPDIR/safe_write_allow.md'
	exit \$rc
"

# 14. Export agent context
check_output "export produces agent context" "## Task:" "$SPEC" export-agent-context "$PROJECT_DIR/fixtures/valid_minimal.json"

# 15. Export dispatch context
check_output "export dispatch produces JSON" "ac_count" "$SPEC" export-agent-context "$PROJECT_DIR/fixtures/valid_minimal.json" --format dispatch

# 15a. FEAT-20: export envelope includes metadata + payload contract
check "spec export envelope produces metadata contract" bash -c "
	out=\"\$('$SPEC' export '$PROJECT_DIR/fixtures/valid_minimal.json' --format envelope 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "metadata" in d and "payload" in d; m=d["metadata"]; assert set(["source_file","schema_version","checksum_sha256","generated_at","payload_format"]).issubset(m.keys()); assert len(m["checksum_sha256"]) == 64'
	[[ \$rc -eq 0 ]]
"

# 15b. FEAT-20: export envelope supports dispatch payload objects
check "spec export envelope with dispatch payload is machine-readable" bash -c "
	out=\"\$('$SPEC' export '$PROJECT_DIR/fixtures/valid_minimal.json' --format envelope --payload-format dispatch 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["metadata"]["payload_format"] == "dispatch"; assert isinstance(d["payload"], dict); assert "ac_count" in d["payload"]'
	[[ \$rc -eq 0 ]]
"

# 15c. SEC-12: dispatch JSON escapes quoted spec content
check "export dispatch escapes quoted content" bash -c "
	out=\"\$('$SPEC' export-agent-context '${PROJECT_DIR}/fixtures/valid_quoted.json' --format dispatch 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d['\''name'\''].startswith('\''Quote '\''); assert chr(34) in d['\''name'\'']; assert '\''quotes'\'' in d['\''goal'\'']'
	[[ \$rc -eq 0 ]]
"

# 16. Nonexistent file
check_fail "validate fails on nonexistent file" "$SPEC" validate "$TMPDIR/nonexistent.yml"

# 17. FEAT-01: spec list finds files
check_output "spec list finds spec files" "basic.spec.yml" "$SPEC" list "$PROJECT_DIR"

# 18. FEAT-01: spec list --json outputs valid JSON
check "spec list --json is valid JSON" bash -c "
	'$SPEC' list '$PROJECT_DIR/examples' --json | python3 -c 'import json,sys; json.load(sys.stdin)'
"

# 18a. FEAT-01: spec list --json reports original spec source paths
check "spec list --json reports source paths" bash -c "
	'$SPEC' list '$PROJECT_DIR/examples' --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d) >= 1; assert all(\"/examples/\" in x[\"file\"] or x[\"file\"].startswith(\"examples/\") for x in d); assert all(\"/tmp\" not in x[\"file\"] for x in d)'
"

# 18b. TEST-JSON: spec list --json strict object shape
check "spec list --json matches contract shape" bash -c "
	'$SPEC' list '$PROJECT_DIR/examples' --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, list); assert len(d) >= 1; req={\"file\",\"name\",\"priority\",\"status\"}; assert all(req.issubset(x.keys()) for x in d); assert all(isinstance(x[\"file\"], str) for x in d); assert all(isinstance(x[\"name\"], str) for x in d); assert all(isinstance(x[\"priority\"], str) for x in d); assert all(isinstance(x[\"status\"], str) for x in d)'
"

# 19. FEAT-06: validate-all processes all specs
check "validate-all passes on project specs" bash -c "
	out=\"\$('$SPEC' validate-all '$PROJECT_DIR/examples' 2>&1)\" || true
	echo \"\$out\" | grep -q 'passed'
"

# 19a. FEAT-13: ci text mode succeeds for valid specs
check "spec ci text mode succeeds" bash -c "
	out=\"\$('$SPEC' ci '$PROJECT_DIR/examples' 2>&1)\"; rc=\$?
	echo \"\$out\" | grep -q 'spec ci: 2 passed, 0 failed, 2 total'
	[[ \$rc -eq 0 ]]
"

# 19b. FEAT-13: ci JSON mode emits valid JSON on success
check "spec ci json mode emits valid JSON" bash -c "
	out=\"\$('$SPEC' ci '$PROJECT_DIR/examples' --format json 2>&1)\"; rc=\$?
	echo "\$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); req={"total","passed","failed","failures"}; assert req.issubset(d.keys()); assert isinstance(d["total"], int); assert isinstance(d["passed"], int); assert isinstance(d["failed"], int); assert isinstance(d["failures"], list); assert d["failed"] == 0 and d["passed"] >= 1 and d["total"] == d["passed"] + d["failed"]'
	[[ \$rc -eq 0 ]]
"

# 19c. FEAT-13: ci GitHub mode succeeds for valid specs
check "spec ci github mode succeeds" bash -c "
	out=\"\$('$SPEC' ci '$PROJECT_DIR/examples' --format github 2>&1)\"; rc=\$?
	echo \"\$out\" | grep -q '::notice::Spec CI: 2/2 passed'
	[[ \$rc -eq 0 ]]
"

# 19c-1. FEAT-13: ci accepts options before directory
check "spec ci accepts option-first argument order" bash -c "
	out=\"\$('$SPEC' ci --format json '$PROJECT_DIR/examples' 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["failed"] == 0; assert d["total"] >= 1'
	[[ \$rc -eq 0 ]]
"

# 19c-1a. SEC-12: ci JSON escapes failure file paths
check "spec ci json escapes unusual failure paths" bash -c "
	ci_dir='${PROJECT_DIR}/_test_ci_json_escape'
	rm -rf \"\$ci_dir\"
	mkdir -p \"\$ci_dir\"
	printf '{\"name\":\"bad\"}' > \"\$ci_dir/bad\\\"name.spec.json\"
	out=\"\$('$SPEC' ci \"\$ci_dir\" --format json 2>&1)\"; rc=\$?
	rm -rf \"\$ci_dir\"
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["failed"] == 1; assert any("bad\\\"name.spec.json" in f for f in d["failures"])'
	[[ \$rc -ne 0 ]]
"

# 19c-2. PERF-03: ci supports --max-files truncation
check "spec ci --max-files truncates scan deterministically" bash -c "
	out=\"\$('$SPEC' ci '$PROJECT_DIR/examples' --format json --max-files 1 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total"] == 1; assert d["truncated"] is True'
	[[ \$rc -eq 0 ]]
"

# 19c-3. PERF-03: ci --fail-fast stops after first failure
check "spec ci --fail-fast stops on first failing spec" bash -c "
	ci_dir='$TMPDIR/ci_fail_fast'
	rm -rf \"\$ci_dir\"
	mkdir -p \"\$ci_dir\"
	cat > \"\$ci_dir/a-invalid.spec.json\" << 'INNEREOF'
{"name":"bad"}
INNEREOF
	cp '$PROJECT_DIR/fixtures/valid_minimal.json' \"\$ci_dir/b-valid.spec.json\"
	out=\"\$('$SPEC' ci \"\$ci_dir\" --format json --fail-fast 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["failed"] == 1; assert d["total"] == 1'
	[[ \$rc -ne 0 ]]
"

# 19c-4. PERF-04: ci --jobs runs parallel validation and keeps stable totals
check "spec ci --jobs validates all specs in parallel" bash -c "
	out=\"\$('$SPEC' ci '$PROJECT_DIR/examples' --format json --jobs 2 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["failed"] == 0; assert d["passed"] == 2; assert d["total"] == 2'
	[[ \$rc -eq 0 ]]
"

# 19c-5. PERF-04: ci --jobs with --max-files remains deterministic
check "spec ci --jobs with --max-files keeps deterministic count" bash -c "
	out=\"\$('$SPEC' ci '$PROJECT_DIR/examples' --format json --jobs 2 --max-files 1 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total"] == 1; assert d["truncated"] is True'
	[[ \$rc -eq 0 ]]
"

# 19c-6. PERF-04: ci --jobs respects fail-fast signal
check "spec ci --jobs --fail-fast truncates on first failure" bash -c "
	ci_dir='$TMPDIR/ci_fail_fast_parallel'
	rm -rf \"\$ci_dir\"
	mkdir -p \"\$ci_dir\"
	cat > \"\$ci_dir/a-invalid.spec.json\" << 'INNEREOF'
{"name":"bad"}
INNEREOF
	cp '$PROJECT_DIR/fixtures/valid_minimal.json' \"\$ci_dir/b-valid.spec.json\"
	cp '$PROJECT_DIR/fixtures/valid_minimal.json' \"\$ci_dir/c-valid.spec.json\"
	out=\"\$('$SPEC' ci \"\$ci_dir\" --format json --jobs 3 --fail-fast 2>&1)\"; rc=\$?
	echo \"\$out\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["failed"] >= 1; assert d["truncated"] is True'
	[[ \$rc -ne 0 ]]
"

# 19d. FEAT-15: graph mermaid mode runs and outputs graph header
check_output "spec graph mermaid mode outputs graph" "graph TD" "$SPEC" graph "$PROJECT_DIR/examples" --format mermaid

# 19e. FEAT-15: graph dot mode runs and outputs digraph header
check_output "spec graph dot mode outputs digraph" "digraph Specs" "$SPEC" graph "$PROJECT_DIR/examples" --format dot

# 19f. FEAT-16: doctor command prints diagnostic header
check_output "spec doctor prints diagnostic header" "Spec Doctor" "$SPEC" doctor

# 19g. FEAT-17: changelog command works with explicit ref
check "spec changelog with explicit ref works" bash -c "
	ref=\$(git rev-parse --verify HEAD~1 2>/dev/null || git rev-parse --verify HEAD) &&
	'$SPEC' changelog \"\$ref\" | grep -q '## Changelog'
"

# 19h. FEAT-18: init-interactive accepts piped answers and creates valid spec
check "spec init-interactive creates a valid spec from prompts" bash -c "
	out='${PROJECT_DIR}/_test_interactive_spec.yml'
	printf 'Interactive Test\nInteractive goal\nhigh\ncli,test\n%s\n' \"\$out\" | '$SPEC' init-interactive >/dev/null 2>&1 &&
	'$SPEC' validate \"\$out\" --quiet >/dev/null 2>&1
	rc=\$?
	rm -f \"\$out\"
	exit \$rc
"

# 19i. FEAT-19: template lifecycle (list/create/delete) works in isolated HOME
check "spec template create and delete in isolated home" bash -c "
	home_dir='${PROJECT_DIR}/_test_template_home'
	rm -rf \"\$home_dir\"
	mkdir -p \"\$home_dir\"
	HOME=\"\$home_dir\" '$SPEC' template list >/dev/null 2>&1 &&
	HOME=\"\$home_dir\" '$SPEC' template create '${PROJECT_DIR}/fixtures/valid_minimal.yml' smoke-template >/dev/null 2>&1 &&
	[[ -f \"\$home_dir/.config/kujo-spec/templates/smoke-template.template.yml\" ]] &&
	HOME=\"\$home_dir\" '$SPEC' template delete smoke-template >/dev/null 2>&1 &&
	[[ ! -f \"\$home_dir/.config/kujo-spec/templates/smoke-template.template.yml\" ]]
	rc=\$?
	rm -rf \"\$home_dir\"
	exit \$rc
"

# 19i-1. FEAT-19: template list prints clean template names
check "spec template list prints normalized names" bash -c "
	home_dir='${PROJECT_DIR}/_test_template_list_home'
	rm -rf \"\$home_dir\"
	mkdir -p \"\$home_dir\"
	HOME=\"\$home_dir\" '$SPEC' template create '${PROJECT_DIR}/fixtures/valid_minimal.yml' smoke-template >/dev/null 2>&1
	out=\"\$(HOME=\"\$home_dir\" '$SPEC' template list 2>&1)\"
	echo \"\$out\" | grep -q '^  smoke-template$'
	! echo \"\$out\" | grep -q 'smoke-template.template'
	rc=\$?
	rm -rf \"\$home_dir\"
	exit \$rc
"

# 19i-1a. SEC-11: template names cannot traverse directories
check_fail "spec template create rejects traversal names" bash -c "
	home_dir='${PROJECT_DIR}/_test_template_traversal_home'
	rm -rf \"\$home_dir\"
	mkdir -p \"\$home_dir\"
	HOME=\"\$home_dir\" '$SPEC' template create '${PROJECT_DIR}/fixtures/valid_minimal.yml' '../escape' >/dev/null 2>&1
	rc=\$?
	rm -rf \"\$home_dir\"
	exit \$rc
"

# 19i-1b. SEC-11: init template names cannot traverse directories
check_fail "spec init rejects traversal template name" bash -c "
	'$SPEC' init --from template:../valid_minimal --output '${PROJECT_DIR}/_test_template_traversal.yml' >/dev/null 2>&1
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_template_traversal.yml'
	exit \$rc
"

# 19i-2. SEC-09: init can use home templates when policy allows
check "spec init loads home template when policy allows" bash -c "
	home_dir='${PROJECT_DIR}/_test_template_source_home'
	rm -rf \"\$home_dir\"
	mkdir -p \"\$home_dir/.config/kujo-spec/templates\"
	cp '${PROJECT_DIR}/fixtures/valid_minimal.yml' \"\$home_dir/.config/kujo-spec/templates/home-only.template.yml\"
	HOME=\"\$home_dir\" '$SPEC' init --from template:home-only --output '${PROJECT_DIR}/_test_home_template.yml' >/dev/null 2>&1
	rc=\$?
	[[ -f '${PROJECT_DIR}/_test_home_template.yml' ]] || rc=1
	rm -f '${PROJECT_DIR}/_test_home_template.yml'
	rm -rf \"\$home_dir\"
	exit \$rc
"

# 19i-3. SEC-09: strict template source blocks home templates
check_fail "spec init strict template mode blocks home templates" bash -c "
	home_dir='${PROJECT_DIR}/_test_template_source_home_block'
	rm -rf \"\$home_dir\"
	mkdir -p \"\$home_dir/.config/kujo-spec/templates\"
	cp '${PROJECT_DIR}/fixtures/valid_minimal.yml' \"\$home_dir/.config/kujo-spec/templates/home-only.template.yml\"
	HOME=\"\$home_dir\" '$SPEC' init --from template:home-only --strict-template-source --output '${PROJECT_DIR}/_test_home_template_blocked.yml' >/dev/null 2>&1
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_home_template_blocked.yml'
	rm -rf \"\$home_dir\"
	exit \$rc
"

# 20. DX-02: validate --quiet produces no output on success
check "validate --quiet is silent on success" bash -c "
	out=\"\$('$SPEC' validate '$PROJECT_DIR/fixtures/valid_minimal.json' --quiet 2>&1)\"
	[[ -z \"\$out\" ]]
"

# 21. TEST-01: YAML spec validation
check "validate passes on valid YAML spec" "$SPEC" validate "$PROJECT_DIR/fixtures/valid_minimal.yml"

# 22. TEST-01: TOML spec validation
check "validate passes on valid TOML spec" "$SPEC" validate "$PROJECT_DIR/fixtures/valid_minimal.toml"

# 23. TEST-02: edge case — empty file returns a deterministic validation error
check "validate rejects an empty file with required-field errors" bash -c "
	empty_file='${PROJECT_DIR}/_test_empty.yml'
	: > \"\$empty_file\"
	out=\$(timeout 10 '$SPEC' validate \"\$empty_file\" 2>&1); rc=\$?
	rm -f \"\$empty_file\"
	[[ \$rc -eq 1 ]] &&
	echo \"\$out\" | grep -q 'Missing required field: name' &&
	echo \"\$out\" | grep -q 'Missing required field: goal'
"
# 24. SCHEMA-01: init generates a UUID v4 id
check "init generates a UUID v4 id" bash -c "
	'$SPEC' init --name test --output '$TMPDIR/with_id.yml' >/dev/null 2>&1
	id=\$(sed -n 's/^id: \"\\([^\"]*\\)\"/\\1/p' '$TMPDIR/with_id.yml')
	echo \"\$id\" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
"

# 25. FEAT-02: spec search by priority
check_output "spec search finds high priority specs" "high" "$SPEC" search --priority high

# 26. FEAT-03: spec status shows draft
check_output "spec status shows draft" "draft" bash -c "
	'$SPEC' init --name stest --output '${PROJECT_DIR}/_test_status_show.yml' >/dev/null 2>&1
	out=\$('${SPEC}' status '${PROJECT_DIR}/_test_status_show.yml' 2>&1)
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_status_show.yml'
	echo \"\$out\"
	exit \$rc
"

# 26a. FEAT-03: status --set updates and is visible immediately
check "spec status --set persists update immediately" bash -c "
	cat > '${PROJECT_DIR}/_test_status_set.json' << 'INNEREOF'
{\"name\":\"status-test\",\"goal\":\"valid goal\",\"status\":\"draft\"}
INNEREOF
	'$SPEC' status '${PROJECT_DIR}/_test_status_set.json' --set review >/dev/null 2>&1 &&
	'$SPEC' status '${PROJECT_DIR}/_test_status_set.json' | grep -q 'review'
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_status_set.json'
	exit \$rc
"

# 26b. FEAT-03: status --set inserts missing YAML status field
check "spec status --set inserts missing YAML status" bash -c "
	cat > '${PROJECT_DIR}/_test_status_missing.yml' << 'INNEREOF'
name: \"status-yaml\"
goal: \"valid goal\"
INNEREOF
	'$SPEC' status '${PROJECT_DIR}/_test_status_missing.yml' --set review >/dev/null 2>&1 &&
	'$SPEC' status '${PROJECT_DIR}/_test_status_missing.yml' | grep -q 'review'
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_status_missing.yml'
	exit \$rc
"

# 26c. FEAT-03: status --set inserts missing TOML status field
check "spec status --set inserts missing TOML status" bash -c "
	cat > '${PROJECT_DIR}/_test_status_missing.toml' << 'INNEREOF'
name = \"status-toml\"
goal = \"valid goal\"
INNEREOF
	'$SPEC' status '${PROJECT_DIR}/_test_status_missing.toml' --set completed >/dev/null 2>&1 &&
	'$SPEC' status '${PROJECT_DIR}/_test_status_missing.toml' | grep -q 'completed'
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_status_missing.toml'
	exit \$rc
"

# 27. FEAT-04: spec convert YAML to JSON
check "spec convert YAML to JSON" bash -c "
	'$SPEC' convert '$PROJECT_DIR/fixtures/valid_minimal.yml' --to json --output '$TMPDIR/conv.json' >/dev/null 2>&1
	python3 -c 'import json; json.load(open(\"$TMPDIR/conv.json\"))'
"
# 28. FEAT-05: spec diff reports the semantic fields that changed
check "spec diff reports changed fields" bash -c "
	out=\$('$SPEC' diff '$PROJECT_DIR/fixtures/valid_minimal.json' '$PROJECT_DIR/fixtures/valid_minimal.yml' 2>&1); rc=\$?
	[[ \$rc -eq 0 ]] &&
	echo \"\$out\" | grep -q '^  goal:' &&
	echo \"\$out\" | grep -q '^  name:' &&
	echo \"\$out\" | grep -q '^  priority:'
"

# 29. KENNEL-04: spec export-eval preserves the Eval suite contract
check "spec export-eval maps eval requirements into checks" bash -c "
	cat > '${PROJECT_DIR}/_test_export_eval.json' << 'INNEREOF'
{\"name\":\"Release gate\",\"goal\":\"Protect the release contract.\",\"eval_requirements\":[{\"description\":\"tests pass\",\"check_type\":\"command_succeeds\",\"params\":{\"command\":\"make test\"}}]}
INNEREOF
	'$SPEC' export-eval '${PROJECT_DIR}/_test_export_eval.json' --output '$TMPDIR/eval_out.json' >/dev/null 2>&1
	rc=\$?
	rm -f '${PROJECT_DIR}/_test_export_eval.json'
	[[ \$rc -eq 0 ]] && python3 -c 'import json; d=json.load(open(\"$TMPDIR/eval_out.json\")); assert d == {\"name\":\"Release gate\",\"description\":\"Protect the release contract.\",\"tests\":[{\"name\":\"tests pass\",\"check\":\"command_succeeds\",\"params\":{\"command\":\"make test\"}}]}'
"

# 30. SCHEMA-02: parent_id field accepted in spec
check "spec with parent_id field validates" bash -c "cd '$PROJECT_DIR' && echo '{\"name\":\"c\",\"goal\":\"g\",\"parent_id\":\"abc\"}' > fixtures/_test_parent.json && '$SPEC' validate fixtures/_test_parent.json >/dev/null 2>&1; rm -f fixtures/_test_parent.json"

# 31. TEST-03: render output contains all expected sections
check "render output has all sections" bash -c "
cat > '$TMPDIR/full.json' << 'INNEREOF'
{"name":"Full Spec","goal":"Test all sections.","background":"bg","scope":"sc","non_goals":["ng1"],"relevant_systems":["sys1"],"likely_files":["f1.kujo"],"acceptance_criteria":["ac1"],"risks":[{"risk":"r1","severity":"low"}],"dependencies":["dep1"],"review_expectations":["rev1"],"human_approval_points":["hap1"],"tags":["t1"],"priority":"high"}
INNEREOF
out=\\$('$SPEC' render '$TMPDIR/full.json' 2>&1)
echo \"\$out\" | grep -q '# Spec: Full Spec' &&
echo \"\$out\" | grep -q '## Goal' &&
echo \"\$out\" | grep -q '## Background' &&
echo \"\$out\" | grep -q '## Scope' &&
echo \"\$out\" | grep -q '## Non-Goals' &&
echo \"\$out\" | grep -q '## Relevant Systems' &&
echo \"\$out\" | grep -q '## Likely Files' &&
echo \"\$out\" | grep -q '## Acceptance Criteria' &&
echo \"\$out\" | grep -q '## Risks' &&
echo \"\$out\" | grep -q '## Dependencies' &&
echo \"\$out\" | grep -q '## Review Expectations' &&
echo \"\$out\" | grep -q '## Human Approval Points'
"

# 32. TEST-04: export agent context has required sections
check "export context has required sections" bash -c "
out=\$('${SPEC}' export-agent-context '${PROJECT_DIR}/fixtures/valid_minimal.json' 2>&1)
echo \"\$out\" | grep -q '## Task:' || exit 1
echo \"\$out\" | grep -q '### Goal' || exit 1
echo \"\$out\" | grep -q '### Priority' || exit 1
echo \"\$out\" | grep -q 'Instructions' || exit 1
"

# 33. TEST-05: schema is valid JSON Schema draft-07
check "schema is valid JSON Schema" bash -c "
python3 -c 'import json; s=json.load(open(\"$PROJECT_DIR/schema/spec.schema.json\")); assert s.get(\"type\")==\"object\"; assert \"name\" in s.get(\"required\",[]); assert \"goal\" in s.get(\"required\",[])'
"

# 33a. Schema-supported lifecycle/tooling fields must not become strict-mode warnings.
check "validate --strict accepts all documented top-level schema fields" bash -c "
cat > '${PROJECT_DIR}/_test_schema_fields.json' << 'INNEREOF'
{"name":"schema fields","goal":"exercise documented fields","updated_at":"2026-08-11T12:00:00Z","completed_at":"2026-08-11T13:00:00Z","estimated_hours":2.5,"children":["child-id"],"metadata":{"owner":"platform"}}
INNEREOF
'$SPEC' validate '${PROJECT_DIR}/_test_schema_fields.json' --strict --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_schema_fields.json'
exit \$rc
"

# 33b. Schema lifecycle status enum is enforced.
check_fail "validate rejects invalid lifecycle status" bash -c "
printf '%s\n' '{"name":"bad status","goal":"reject it","status":"shipping"}' > '${PROJECT_DIR}/_test_bad_status.json'
'$SPEC' validate '${PROJECT_DIR}/_test_bad_status.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_bad_status.json'
exit \$rc
"

# 33c. Schema UUID v4 pattern is enforced.
check_fail "validate rejects malformed spec id" bash -c "
printf '%s\n' '{"name":"bad id","goal":"reject it","id":"not-a-uuid"}' > '${PROJECT_DIR}/_test_bad_id.json'
'$SPEC' validate '${PROJECT_DIR}/_test_bad_id.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_bad_id.json'
exit \$rc
"

# 33d. Numeric schema fields reject strings.
check_fail "validate rejects non-numeric estimated_hours" bash -c "
printf '%s\n' '{"name":"bad hours","goal":"reject it","estimated_hours":"two"}' > '${PROJECT_DIR}/_test_bad_hours.json'
'$SPEC' validate '${PROJECT_DIR}/_test_bad_hours.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_bad_hours.json'
exit \$rc
"

# 33e. Runtime validation matches the schema's non_goals item limit.
check_fail "validate rejects more than 100 non-goals" bash -c "
python3 -c 'import json; json.dump({"name":"too many","goal":"reject it","non_goals":["x"]*101}, open("${PROJECT_DIR}/_test_many_non_goals.json","w"))'
'$SPEC' validate '${PROJECT_DIR}/_test_many_non_goals.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_many_non_goals.json'
exit \$rc
"

# 33f. Arrays declared as string arrays reject non-string elements.
check_fail "validate rejects non-string array items" bash -c "
printf '%s\n' '{"name":"bad tags","goal":"reject it","tags":[7]}' > '${PROJECT_DIR}/_test_bad_tags.json'
'$SPEC' validate '${PROJECT_DIR}/_test_bad_tags.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_bad_tags.json'
exit \$rc
"

# 33g. Structured dependencies enforce their object contract.
check_fail "validate rejects malformed structured dependencies" bash -c "
printf '%s\n' '{"name":"bad dep","goal":"reject it","dependencies":[{"type":"unknown"}]}' > '${PROJECT_DIR}/_test_bad_dependency.json'
'$SPEC' validate '${PROJECT_DIR}/_test_bad_dependency.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_bad_dependency.json'
exit \$rc
"

# 33h. Risk entries must be objects, not arbitrary scalars.
check_fail "validate rejects non-object risks" bash -c "
printf '%s\n' '{"name":"bad risk","goal":"reject it","risks":["oops"]}' > '${PROJECT_DIR}/_test_bad_risk.json'
'$SPEC' validate '${PROJECT_DIR}/_test_bad_risk.json' --quiet
rc=\$?
rm -f '${PROJECT_DIR}/_test_bad_risk.json'
exit \$rc
"

# 33i. Convert must reject formats it cannot produce.
check_fail "convert rejects unsupported target format" "$SPEC" convert "$PROJECT_DIR/fixtures/valid_minimal.json" --to xml --output "$TMPDIR/invalid.xml"

# 33j. Template imports honor the requested output format without requiring --name.
check "init template converts to requested format without name override" bash -c "
template_dir='${PROJECT_DIR}/specs/templates'
mkdir -p \"\$template_dir\"
cp '${PROJECT_DIR}/fixtures/valid_minimal.json' \"\$template_dir/_test_format.template.json\"
'$SPEC' init --from template:_test_format --format toml --output '${PROJECT_DIR}/_test_template_format.toml' >/dev/null 2>&1
rc=\$?
grep -q '^name = ' '${PROJECT_DIR}/_test_template_format.toml' || rc=1
rm -f \"\$template_dir/_test_format.template.json\" '${PROJECT_DIR}/_test_template_format.toml'
exit \$rc
"

# 34. DX-03: validate --strict treats warnings as errors
check_fail "validate --strict fails on warnings" bash -c "
cat > '$TMPDIR/warn.json' << 'INNEREOF'
{"name":"warn","goal":"test","eval_requirements":[{"description":"check","check_type":"unknown_type"}]}
INNEREOF
'$SPEC' validate '$TMPDIR/warn.json' --strict >/dev/null 2>&1
"

# 34a. SEC-10: unknown top-level field warns in default mode
check_output "validate warns on unknown top-level fields in default mode" "Unknown top-level field" bash -c "
cat > '${PROJECT_DIR}/_test_unknown_top_level.json' << 'INNEREOF'
{\"name\":\"warn\",\"goal\":\"test\",\"unknown_field\":\"value\"}
INNEREOF
'$SPEC' validate '${PROJECT_DIR}/_test_unknown_top_level.json' --json
rc=\$?
rm -f '${PROJECT_DIR}/_test_unknown_top_level.json'
exit \$rc
"

# 34b. SEC-10: strict mode fails when unknown top-level fields are present
check_fail "validate --strict fails on unknown top-level fields" bash -c "
cat > '${PROJECT_DIR}/_test_unknown_top_level_strict.json' << 'INNEREOF'
{"name":"warn","goal":"test","unknown_field":"value"}
INNEREOF
'$SPEC' validate '${PROJECT_DIR}/_test_unknown_top_level_strict.json' --strict >/dev/null 2>&1
rc=\$?
rm -f '${PROJECT_DIR}/_test_unknown_top_level_strict.json'
exit \$rc
"

# 35. KENNEL-05: spec export-dispatch produces JSON
check "spec export-dispatch produces JSON" bash -c "
out=\$('${SPEC}' export-agent-context '${PROJECT_DIR}/fixtures/valid_minimal.json' --format dispatch 2>&1)
echo \"\$out\" | python3 -c 'import json,sys; json.load(sys.stdin)'
"

# 36. TEST-02: Edge case — binary file handled gracefully (should fail, not crash)
check_fail "validate binary file fails cleanly" bash -c "
dd if=/dev/urandom of='${PROJECT_DIR}/_test_binary.bin' bs=1024 count=1 2>/dev/null
cp '${PROJECT_DIR}/_test_binary.bin' '${PROJECT_DIR}/_test_binary.json'
${SPEC} validate '${PROJECT_DIR}/_test_binary.json' >/dev/null 2>&1; rc=\$?
rm -f '${PROJECT_DIR}/_test_binary.bin' '${PROJECT_DIR}/_test_binary.json'
exit \$rc
"

# 37. TEST-02: Edge case — large spec validates
check "validate large spec passes" bash -c "
python3 -c 'import json; spec={\"name\":\"Large\",\"goal\":\"A\"*4000,\"version\":\"0.1.0\",\"priority\":\"medium\"}; json.dump(spec, open(\"${PROJECT_DIR}/_test_large.json\",\"w\"))'
${SPEC} validate '${PROJECT_DIR}/_test_large.json' >/dev/null 2>&1; rc=\$?
rm -f '${PROJECT_DIR}/_test_large.json'
exit \$rc
"

# 38. TEST-02: Edge case — name > 200 chars fails validation
check_fail "validate rejects name over 200 chars" bash -c "
python3 -c 'import json; spec={\"name\":\"A\"*201,\"goal\":\"Valid goal\",\"version\":\"0.1.0\",\"priority\":\"medium\"}; json.dump(spec, open(\"${PROJECT_DIR}/_test_long_name.json\",\"w\"))'
${SPEC} validate '${PROJECT_DIR}/_test_long_name.json' >/dev/null 2>&1; rc=\$?
rm -f '${PROJECT_DIR}/_test_long_name.json'
exit \$rc
"

# 39. TEST-02: Edge case — goal > 5000 chars fails validation
check_fail "validate rejects goal over 5000 chars" bash -c "
python3 -c 'import json; spec={\"name\":\"Valid\",\"goal\":\"A\"*5001,\"version\":\"0.1.0\",\"priority\":\"medium\"}; json.dump(spec, open(\"${PROJECT_DIR}/_test_long_goal.json\",\"w\"))'
${SPEC} validate '${PROJECT_DIR}/_test_long_goal.json' >/dev/null 2>&1; rc=\$?
rm -f '${PROJECT_DIR}/_test_long_goal.json'
exit \$rc
"

# 40. TEST-02: Edge case — directory instead of file
check_fail "validate rejects directory instead of file" bash -c "
mkdir -p '${PROJECT_DIR}/_test_dir'
${SPEC} validate '${PROJECT_DIR}/_test_dir' >/dev/null 2>&1; rc=\$?
rmdir '${PROJECT_DIR}/_test_dir' 2>/dev/null
exit \$rc
"

# 41. TEST-02: Edge case — symlink to valid spec works
check "validate follows symlink to valid spec" bash -c "
ln -sf '${PROJECT_DIR}/fixtures/valid_minimal.json' '${PROJECT_DIR}/_test_linked.json'
${SPEC} validate '${PROJECT_DIR}/_test_linked.json' >/dev/null 2>&1; rc=\$?
rm -f '${PROJECT_DIR}/_test_linked.json'
exit \$rc
"

# 41a. SEC-02: symlink escape outside project is blocked
check_fail "validate rejects symlink resolving outside project" bash -c "
ln -sf /etc/passwd '${PROJECT_DIR}/_test_outside_link.json'
${SPEC} validate '${PROJECT_DIR}/_test_outside_link.json' >/dev/null 2>&1; rc=\$?
rm -f '${PROJECT_DIR}/_test_outside_link.json'
exit \$rc
"

# 42. TEST-02: Edge case — structured dependencies render
check "render handles structured dependencies" bash -c "
cat > '${PROJECT_DIR}/_test_deps.json' << 'INNEREOF'
{\"name\":\"Dep Test\",\"goal\":\"Test deps.\",\"dependencies\":[{\"type\":\"blocked_by\",\"description\":\"API must be ready\",\"spec_id\":\"abc-123\"},{\"type\":\"blocks\",\"description\":\"Frontend work\"}]}
INNEREOF
out=\$(${SPEC} render '${PROJECT_DIR}/_test_deps.json' 2>&1); rc=\$?
rm -f '${PROJECT_DIR}/_test_deps.json'
echo \"\$out\" | grep -q 'Blocked by' || exit 1
echo \"\$out\" | grep -q 'Blocks' || exit 1
echo \"\$out\" | grep -q 'abc-123' || exit 1
exit \$rc
"

# 43. FEAT-17: changelog command works in repositories without tags
check "spec changelog falls back when no tags exist" bash -c "
	repo='${TMPDIR}/untagged_repo'
	rm -rf \"\$repo\"
	mkdir -p \"\$repo\"
	cd \"\$repo\"
	git init -q
	git config user.email test@example.com
	git config user.name test
	echo 'seed' > README.md
	git add README.md
	git commit -q -m 'feat: initial commit'
	out=\$('${SPEC}' changelog 2>&1)
	echo \"\$out\" | grep -q 'No tags found.' &&
	echo \"\$out\" | grep -q '## Changelog'
"

# 44. PERF-05: benchmark emits machine-readable runtime summary
check "benchmark writes ci_runtime_ms summary" bash -c "
	summary='${TMPDIR}/benchmark_summary.json'
	SPEC_BENCH_SUMMARY_FILE=\"\$summary\" '$PROJECT_DIR/tests/benchmark.sh' 2 30 local >/dev/null 2>&1
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert \"ci_runtime_ms\" in d and isinstance(d[\"ci_runtime_ms\"], int); assert \"trend_budget_ms\" in d' \"\$summary\"
"

# 45. FEAT-21: shell completions stay aligned with key command surface
check "completion parity script passes" bash -c "'$PROJECT_DIR/scripts/verify_completion_parity.sh' >/dev/null"

# Summary
report_results "Results"
