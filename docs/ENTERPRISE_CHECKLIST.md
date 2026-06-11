# Spec — Enterprise Readiness Checklist

> **Purpose:** Track improvements to make Spec a production-grade, universally useful tool that showcases the Kujo language's capabilities. Work through items by tier.
>
> **Status:** historical planning checklist (not release sign-off). Current baseline snapshot: 53 tests passing and expanded CLI surface. Verify each item against current code before treating as complete.

---

## Tier 0: Critical (Security & Correctness)

### [x] SEC-05: Add Python stdin/sys.argv hardening to all inline Python calls

**Goal:** Several inline Python blocks in `scripts/spec` interpolate shell variables directly into Python string literals (e.g., `open('$tmp')`). While the shell-sourced values are project-internal and sanitized upstream, defense-in-depth demands passing values via `sys.argv` or environment variables.

**Files:** `scripts/spec` (all inline `python3 -c "..."` calls with `$var` interpolation)

**Details:**
- Audit every inline `python3 -c` call for `$var` or `'$var'` interpolation
- Convert to `python3 -c '...' - "$var"` pattern where `sys.argv[1]` receives the value
- Priority: `_init_from` stdin handler, `cmd_info`, `cmd_status`, `cmd_convert`, `cmd_diff`, `cmd_export_eval`, `cmd_list` `_spec_field` helper

**Verification:**
- All 46 tests pass
- Manual test: spec with special characters in name still works
- No shell injection possible via spec file content

---

### [x] SEC-06: Add timeout to external command invocations

**Goal:** `spec watch` runs indefinitely, `spec validate` invokes the Kujo runtime — neither has a timeout. A hung process could block CI pipelines indefinitely.

**Files:** `scripts/spec` (`cmd_validate`, `cmd_watch`)

**Details:**
- Add `SPEC_TIMEOUT` env var (default: 30s)
- Wrap `$KUJO_BIN run ...` calls in `timeout` or a background-kill pattern
- `spec watch` should have a `--max-iterations` flag to prevent infinite loops in CI

**Verification:**
- Simulate a hung Kujo runtime; verify timeout fires
- `spec validate` with timeout exits non-zero with clear message

---

### [x] SEC-07: Validate spec file content before writing in `spec status --set`

**Goal:** `cmd_status --set` uses `sed -i ''` to modify spec files in place. If the sed pattern fails silently (e.g., the status field is nested in a TOML table), the file could be corrupted without detection.

**Files:** `scripts/spec` (`cmd_status`)

**Details:**
- After `sed -i`, re-validate the file with `spec validate --quiet`
- If validation fails, restore from a backup and exit with error
- For JSON format, use `python3` to modify in place instead of sed

**Verification:**
- Set status on valid spec → passes
- Corrupt a spec mid-edit → restore succeeds, error reported

---

## Tier 1: Performance & Scalability

### [x] PERF-01: Batch spec_to_json in cmd_list to avoid N separate Python processes

**Goal:** `cmd_list` spawns a Python process for every spec file to extract name/priority. For 100+ specs, this is slow. Parse all specs in a single Python invocation.

**Files:** `scripts/spec` (`cmd_list`, `_spec_field` helper)

**Details:**
- Instead of `_spec_field` spawning `python3` per spec, collect all JSON files and pass them to a single `python3` script
- Use `python3 -c '...'` that iterates over all files and outputs TSV/JSON
- Or: write a standalone `scripts/spec_list.py` that accepts multiple file args

**Verification:**
- `spec list` on 100 specs finishes in under 2 seconds (currently ~30s)
- `spec list --json` output identical to current behavior

---

### [x] PERF-02: Cache spec-to-JSON conversion in a tempdir for repeated operations

**Goal:** `spec list` followed by `spec validate-all` converts every spec to JSON twice. Cache conversions in `$TMPDIR/.spec_cache/` keyed by file mtime.

**Files:** `scripts/spec` (`spec_to_json`)

**Details:**
- Before converting, check if a cached JSON exists with matching mtime
- Use `$TMPDIR/spec_cache/<sha256-of-path>.json` as cache key
- Invalidate on mtime change
- Add `--no-cache` flag to force re-conversion

**Verification:**
- First run converts all specs
- Second run with unchanged specs uses cache (faster)
- Modified spec gets re-converted

---

### [x] PERF-03: Reduce Python startup overhead by using a persistent helper script

**Goal:** Each inline `python3 -c "..."` call incurs ~50ms Python startup overhead. For commands that make multiple calls (like `cmd_info` making 12 separate calls), this adds up.

**Files:** Create `scripts/spec_helpers.py`, update `scripts/spec`

**Details:**
- Create `scripts/spec_helpers.py` that accepts a command and args:
  - `python3 scripts/spec_helpers.py get-field <json-file> <field> [default]`
  - `python3 scripts/spec_helpers.py get-count <json-file> <array-field>`
  - `python3 scripts/spec_helpers.py list-fields <json-file> <field1,field2,...>`
- Replace inline `python3 -c` calls with invocations of this script
- Script imports once, runs fast

**Verification:**
- All 46 tests pass
- `spec info` completes in under 200ms (currently ~600ms with 12 Python calls)

---

## Tier 2: Functionality & User Experience

### [x] FEAT-10: Add `spec init --interactive` mode

**Goal:** New users shouldn't need to memorize spec fields. An interactive wizard would walk them through creating a spec.

**Files:** `scripts/spec` (new `cmd_init --interactive` branch)

**Details:**
- Prompt for each field: name, goal, priority, tags, background, scope
- Show defaults and allow skipping
- Validate input as they type (e.g., priority must be one of critical/high/medium/low)
- At the end, show a preview and confirm before writing

**Verification:**
- Run `spec init --interactive` → prompted for fields
- Accept defaults → valid spec created
- Provide custom values → reflected in output

---

### [x] FEAT-11: Add `spec template` command to manage templates

**Goal:** `spec init --from template:name` currently looks for `specs/templates/<name>.template.yml`. There's no way to list, create, or edit templates.

**Files:** `scripts/spec` (new `cmd_template`)

**Details:**
- `spec template list` — list available templates
- `spec template create <name>` — create a new template from an existing spec
- `spec template edit <name>` — open template in $EDITOR
- `spec template delete <name>` — remove a template
- Store templates in `~/.config/kujo-spec/templates/` (user-level) and `specs/templates/` (project-level)

**Verification:**
- Create a template from a spec
- `spec template list` shows it
- `spec init --from template:name` uses it

---

### [x] FEAT-12: Add `spec export` command with multiple output formats

**Goal:** Currently export options are scattered: `export-agent-context` (text/dispatch), `export-eval` (eval suite), `render` (markdown). A unified `spec export` command would be cleaner.

**Files:** `scripts/spec` (new `cmd_export`)

**Details:**
- `spec export <file> --format markdown` → same as `spec render`
- `spec export <file> --format agent` → same as `spec export-agent-context`
- `spec export <file> --format dispatch` → dispatch JSON
- `spec export <file> --format eval` → eval suite
- `spec export <file> --format html` → HTML rendering (new)
- Keep old commands as aliases for backward compatibility

**Verification:**
- All export formats produce correct output
- Old command aliases still work

---

### [x] FEAT-13: Add `spec ci` command for CI/CD integration

**Goal:** CI pipelines need a single command that does everything: validate all specs, check format consistency, and produce a summary report.

**Files:** `scripts/spec` (new `cmd_ci`)

**Details:**
- `spec ci` — validate all specs, exit non-zero on any failure
- `spec ci --format github` — output GitHub Actions annotations
- `spec ci --format gitlab` — output GitLab CI artifacts
- `spec ci --strict` — warnings become errors
- Produces a JSON summary file for downstream tools

**Verification:**
- Run in a project with valid specs → exits 0, no output
- Run in a project with an invalid spec → exits 1, shows annotation
- GitHub format produces `::error file=...::message` output

---

### [ ] FEAT-14: Add `spec serve` for local spec browsing

**Goal:** Browse specs in a local web UI. Useful for teams to review specs without the CLI.

**Files:** Create `src/server.kujo`, update `scripts/spec`

**Details:**
- `spec serve` — starts a local HTTP server on port 9393
- Lists all specs with filtering by status/priority/tag
- Renders individual specs as styled HTML
- No external dependencies (pure Kujo + shell)
- Auto-reloads on file changes

**Verification:**
- `spec serve` → opens browser at http://localhost:9393
- Spec list shows all specs
- Click a spec → rendered view

---

### [x] FEAT-15: Add spec relationships and visualization

**Goal:** `parent_id` and `children` fields exist in the schema but have no tooling support. `dependencies` with `blocks`/`blocked_by` exist but aren't visualized.

**Files:** `src/render.kujo`, `scripts/spec` (new `cmd_graph`)

**Details:**
- `spec graph` — output a Mermaid or DOT graph of spec relationships
- `spec graph --format mermaid` → markdown-compatible Mermaid diagram
- `spec graph --format dot` → Graphviz DOT format
- Show parent/child hierarchy and blocks/blocked_by edges
- Color nodes by status (draft=gray, ready=blue, in-progress=yellow, completed=green)

**Verification:**
- Create parent + child specs
- `spec graph` shows hierarchy
- Output renders correctly in GitHub Markdown

---

## Tier 3: Developer Experience & Documentation

### [x] DX-04: Add shell completion for all flags and subcommands

**Goal:** Completions exist (bash/zsh/fish) but may not cover newest flags like `--from`, `--json`, `--strict`, `--quiet`, `--interactive`.

**Files:** `completions/spec.bash`, `completions/spec.zsh`, `completions/spec.fish`

**Details:**
- Update all three completion files to include all 14 commands
- Add flag completions: `--format`, `--output`, `--name`, `--from`, `--json`, `--quiet`, `--strict`, `--dir`, `--max-depth`, `--tag`, `--priority`, `--query`, `--set`, `--to`, `--dry-run`
- Add file path completion for validate/render/export/info/status/watch commands
- Add `--from` value completion (json:, template:, github:, -)

**Verification:**
- Source completion file
- `spec <TAB>` shows all 14 commands
- `spec validate <TAB>` completes .yml/.yaml/.toml/.json files
- `spec init --from <TAB>` shows source type prefixes

---

### [x] DX-05: Add `spec doctor` to diagnose environment issues

**Goal:** New users often hit "KUJO_BIN not set" or "Python3 not found" errors. A diagnostic command would help.

**Files:** `scripts/spec` (new `cmd_doctor`)

**Details:**
- Check: Kujo runtime available and correct version
- Check: Python 3 available with yaml module
- Check: Required directories exist (src/, schema/, scripts/)
- Check: File permissions on spec script
- Check: Common spec file locations found
- Output: green checkmarks for OK, red X for issues with fix instructions

**Verification:**
- Run with correct setup → all green
- Unset KUJO_BIN → red X with fix instruction
- Missing yaml module → red X with `pip install pyyaml`

---

### [x] DX-06: Add changelog automation

**Goal:** CHANGELOG.md exists but requires manual updates. Automate from git history.

**Files:** `scripts/spec` (new `cmd_changelog`), `CHANGELOG.md`

**Details:**
- `spec changelog` — generate changelog from git log since last tag
- Group by conventional commit type (feat:, fix:, docs:, etc.)
- `spec changelog --version 0.2.0` — generate for a specific version
- Output format matches CHANGELOG.md conventions

**Verification:**
- Make some commits with conventional commit messages
- `spec changelog` produces grouped, formatted output

---

### [x] DOCS-05: Add architecture decision records (ADRs)

**Goal:** Document why key architectural decisions were made. Helps contributors understand the codebase.

**Files:** Create `docs/adr/` directory

**Details:**
- ADR-001: Why shell script CLI instead of pure Kujo
- ADR-002: Why JSON as internal interchange format
- ADR-003: Why YAML as recommended spec format
- ADR-004: Why Python for YAML/TOML parsing instead of Kujo-native parsers
- ADR-005: Why cross-module imports (and the temporary inline duplication)

**Verification:**
- 5 ADR files exist in `docs/adr/`
- Each follows the standard ADR format (Title, Status, Context, Decision, Consequences)

---

## Tier 4: Testing & Quality Assurance

### [ ] TEST-07: Add integration tests for full workflows

**Goal:** Current tests cover individual commands. Add end-to-end workflow tests.

**Files:** `tests/integration.sh` (new)

**Details:**
- Test: `init → validate → render → export → diff` pipeline
- Test: `init --from stdin` → validate → status update → validate
- Test: `init --from json:` → convert to TOML → validate
- Test: `list → validate-all` on a directory of specs
- Test: `search --priority high` finds correct specs

**Verification:**
- All integration tests pass
- Tests are idempotent (clean up after themselves)

---

### [ ] TEST-08: Add property-based/fuzz tests for validation

**Goal:** Ensure the validator handles arbitrary JSON gracefully — no crashes, no hangs.

**Files:** `tests/fuzz.sh` (new)

**Details:**
- Generate random JSON objects with Python
- Feed them to `spec validate`
- Verify: always exits 0 or 1 (never crashes, never hangs)
- Verify: output is always valid JSON with `valid`, `errors`, `warnings` keys
- Run 1000 iterations per test run

**Verification:**
- 1000 random inputs → 0 crashes, 0 hangs
- All outputs are syntactically valid JSON

---

### [ ] TEST-09: Add test for all 14 commands in help output

**Goal:** Ensure `spec help` lists every command and every command works.

**Files:** `tests/run_tests.sh`

**Details:**
- Parse `spec help` output and extract command names
- For each command, run `spec <command>` (with no args where safe) and verify it doesn't crash
- Verify count matches expected (14)

**Verification:**
- Test extracts 14 commands from help
- Each command runs without crashing

---

## Tier 5: Distribution & Ecosystem

### [ ] REL-04: Create GitHub Actions CI workflow

**Goal:** Automated testing on every push and PR.

**Files:** Create `.github/workflows/ci.yml`

**Details:**
- Trigger: push to main, PR to main
- Steps: checkout, set up Kujo runtime, run test suite, run quality gates
- Matrix: test on ubuntu-latest, macos-latest
- Upload test results as artifact

**Verification:**
- Push triggers CI run
- Both OS matrix entries pass
- PR shows check status

---

### [ ] REL-05: Add Homebrew formula

**Goal:** `brew install kujolang/spec/spec` for macOS users.

**Files:** Submit to homebrew-core or create a tap

**Details:**
- Create `homebrew/spec.rb` formula
- Dependencies: python3, kujo (if available in brew)
- Install: copies scripts/ and src/ to prefix, symlinks spec to bin
- Test: `spec version` exits 0

**Verification:**
- `brew install ./homebrew/spec.rb` works
- `spec version` prints version

---

### [ ] REL-06: Publish to npm (for Node.js users)

**Goal:** `npx spec init` for JavaScript/TypeScript projects.

**Files:** Create `package.json` at root

**Details:**
- Lightweight npm package that downloads and installs the shell script
- `bin.spec` points to installed script
- Postinstall: check for Kujo runtime, print guidance if missing
- Version: sync with VERSION file

**Verification:**
- `npm install -g kujo-spec` works
- `spec version` prints version

---

## Tier 6: Kujo Language Showcase

These items specifically make Spec a "shining star example" of the Kujo language.

### [ ] SHOW-01: Rewrite CLI in pure Kujo

**Goal:** The shell script CLI is pragmatic but doesn't showcase Kujo. A pure Kujo CLI would be a powerful demonstration.

**Files:** Create `src/cli.kujo` as new entry point

**Details:**
- Implement all 14 commands in Kujo (no shell wrapper)
- Handle YAML/TOML parsing via Kujo-native parsers or embedded Python calls
- Use Kujo's arg parsing, file I/O, and JSON handling
- Keep the shell script as a compatibility fallback

**Verification:**
- All 46 tests pass with Kujo CLI
- Behavior identical to shell CLI
- `kennel.toml` entry point updated

---

### [ ] SHOW-02: Add Kujo-native YAML parser

**Goal:** Remove Python dependency for YAML parsing. A Kujo-native YAML subset parser would showcase the language's string processing.

**Files:** Create `src/yaml.kujo`

**Details:**
- Parse the YAML subset that Spec uses (flat key: value, lists, no anchors/tags)
- Handle strings, numbers, booleans, null
- Error on unsupported YAML features with clear messages
- Benchmark: faster than Python yaml.safe_load for spec-sized files

**Verification:**
- Parses all fixtures/*.yml correctly
- Rejects invalid YAML with clear error
- `spec validate` works without Python for YAML specs

---

### [ ] SHOW-03: Add Kujo-native TOML parser

**Goal:** Same as YAML parser — remove Python dependency for TOML.

**Files:** Create `src/toml.kujo`

**Details:**
- Parse the TOML subset that Spec uses (key = value, arrays)
- Handle strings, numbers, booleans, dates
- Error on unsupported TOML features

**Verification:**
- Parses all fixtures/*.toml correctly
- `spec validate` works without Python for TOML specs

---

### [ ] SHOW-04: Publish spec as a kennel package with full API

**Goal:** Other Kujo projects should be able to `import spec.validate` or `import spec.render` directly.

**Files:** `kennel.toml`, `src/common.kujo`

**Details:**
- Ensure all `export func` signatures are stable and documented
- Add `src/common.kujo` to `[package.exports]` in kennel.toml
- Add version compatibility guarantees to docs
- Add import examples to README

**Verification:**
- Another Kujo project can `from spec import validate_spec`
- `validate_spec(spec_dict)` returns `{valid, errors, warnings}`

---

### [ ] SHOW-05: Create a "Powered by Spec" example gallery

**Goal:** Show real-world usage that attracts developers to both Spec and the Kujo language.

**Files:** Create `examples/gallery/` with subdirectories

**Details:**
- Example 1: CI pipeline that gates PRs on spec validation
- Example 2: Spec-driven development workflow (spec → agent → implementation)
- Example 3: Multi-service architecture described entirely in specs
- Example 4: Spec-to-documentation pipeline for a real project
- Example 5: Using specs for code review checklists

**Verification:**
- Each example has a README
- Each example is self-contained and runnable
- Gallery linked from main README

---

## Summary

| Tier | Items | Description |
|------|-------|-------------|
| 0 — Critical | 3 | Security hardening |
| 1 — Performance | 3 | Speed and resource optimization |
| 2 — Functionality | 6 | New features and UX improvements |
| 3 — Developer Experience | 3 | Tooling, diagnostics, docs |
| 4 — Testing | 3 | Integration, fuzz, coverage |
| 5 — Distribution | 3 | CI, brew, npm |
| 6 — Kujo Showcase | 5 | Pure Kujo rewrites, language demo |

**Total: 26 improvement items across 6 tiers.**
