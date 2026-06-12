# Spec

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/kujolang/spec)
[![Contract](https://img.shields.io/badge/contract-v0.1.0-green)](https://github.com/kujolang/spec)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

> **v0.1.0** | Contract v0.1.0 | JSON Schema | CLI tool | YAML/TOML/JSON support | Agent context export | Generated command inventory

**Spec** defines task contracts, acceptance criteria, expected outputs, and agent-readable work instructions for AI-native development.

A `.spec.yml` file turns human instructions into a clear, reviewable task contract.

Prioritize copyable examples over tests: examples should model the most token-efficient idioms we want agents to imitate.

## Why This Exists

Most agent failures start with vague requirements, not code generation.

Spec gives Kujo a native task-contract format before implementation starts:

- **Goal** — the primary objective
- **Background** — context and motivation
- **Scope** — what's in and out of scope
- **Acceptance criteria** — verifiable conditions for completion
- **Eval requirements** — automated checks that validate outcomes
- **Risks** — known risks with severity and mitigations
- **Dependencies** — what must be available before starting
- **Review expectations** — how the work will be reviewed
- **Human approval points** — where humans must sign off

## Quick Start

```bash
export PATH="/path/to/kujo-spec/scripts:$PATH"

mkdir -p specs
cat > specs/dark-mode.spec.yml <<'YAML'
name: "Add dark mode"
goal: "Add a theme toggle and persist the selected color scheme."
priority: "medium"
acceptance_criteria:
  - "Users can switch between light and dark themes"
  - "The selected theme persists after reload"
YAML

spec validate specs/dark-mode.spec.yml
spec render specs/dark-mode.spec.yml
spec export-agent-context specs/dark-mode.spec.yml
```

Expected validation output:

```text
Validating: specs/dark-mode.spec.yml
PASS: Spec is valid
```

## Requirements

- **Kujo language runtime** v0.1.0+ (set `KUJO_BIN` env var or ensure it's at the default path)
- **Python 3** (for YAML/TOML parsing; JSON specs work without it)
- No API keys or external services needed

## Commands

The authoritative command inventory is generated from `spec help`:

- `docs/COMMAND_INVENTORY.md`

Regenerate it after command-surface changes:

```bash
bash scripts/generate_command_inventory.sh write
```

Version note:

- Use `spec version` for version output.
- `--version` is not implemented.

## Options

| Option | Description |
|---|---|
| `--format yaml\|toml\|json` | Spec file format (default: yaml) |
| `--output <path>` | Output file path |
| `--name <name>` | Spec name (for init) |
| `--from <source>` | Import spec from external source (init) |
| `--strict-template-source` | Restrict init template lookup to project templates only |
| `--unsafe-write` | Allow writes outside project root when safe-write mode is active |
| `--payload-format agent\|dispatch` | Envelope payload format for `spec export --format envelope` |
| `--json` | Machine-readable JSON output (validate, version, info, list) |
| `--quiet` | Suppress output on success (validate) |
| `--strict` | Treat warnings as errors (validate) |
| `--max-files <n>` | Limit `spec ci` scan count for large repos |
| `--fail-fast` | Stop `spec ci` on first failure |
| `--jobs <n>` | Run `spec ci` validation in parallel workers |

Safe-write mode:
- `SPEC_SAFE_WRITE=auto|on|off` controls output-path restrictions.
- `auto` (default) enables restrictions for `spec ci` command context.
- Use `--unsafe-write` to explicitly override per command.

Template source policy:
- `SPEC_TEMPLATE_SOURCE_POLICY=allow-home|project-only` controls whether `spec init --from template:<name>` can load templates from `$HOME/.config/kujo-spec/templates`.
- Use `--strict-template-source` for one-off project-only resolution.

CI scaling controls:
- `spec ci --max-files <n>` bounds scan time in very large repositories.
- `spec ci --fail-fast` exits early on first invalid spec to shorten feedback loops.
- `spec ci --jobs <n>` enables deterministic parallel validation for enterprise-scale trees.
- Flags can be combined with any argument order, for example: `spec ci --format json ./specs --max-files 200 --jobs 4`.

### Import Sources (`spec init --from`)

| Source | Example | Description |
|---|---|---|
| `-` | `cat spec.json \| spec init --from -` | Read JSON spec from stdin |
| `json:<file>` | `spec init --from json:input.json` | Import from a JSON file |
| `template:<name>` | `spec init --from template:feature` | Use a template from `specs/templates/` |
| `github:<o/r/n>` | `spec init --from github:kujolang/spec/1` | Fetch a GitHub issue (requires `gh` CLI) |

### Export Envelope Format

Use `spec export --format envelope` when automation needs payload + metadata in one JSON object.

Spec pairs well with Eval when you want the work to be verifiable, not just described.

Metadata fields:
- `source_file`
- `schema_version`
- `checksum_sha256`
- `generated_at`
- `payload_format`

Example:

```bash
spec export spec.yml --format envelope --payload-format dispatch --output artifacts/spec.envelope.json
```

## File Formats

Spec supports three formats:

### YAML (`.spec.yml`, `.spec.yaml`) — Recommended

```yaml
name: "Add user avatar upload"
goal: "Implement avatar upload endpoint for user profiles."
version: "0.1.0"
background: "Users have requested this feature since Q1."
scope: "POST /api/users/:id/avatar with JPEG/PNG support up to 5MB."
non_goals:
  - "Animated GIF support"
  - "Avatar cropping UI"
acceptance_criteria:
  - "POST returns 201 with avatar URL"
  - "Uploads >5MB return 413"
priority: "high"
tags:
  - "api"
  - "users"
```

### JSON (`.spec.json`)

```json
{
  "name": "Add user avatar upload",
  "goal": "Implement avatar upload endpoint for user profiles.",
  "version": "0.1.0",
  "priority": "high",
  "tags": ["api", "users"]
}
```

### TOML (`.spec.toml`)

```toml
name = "Add user avatar upload"
goal = "Implement avatar upload endpoint for user profiles."
version = "0.1.0"
priority = "high"
tags = ["api", "users"]
```

## Schema

The full JSON Schema is at [`schema/spec.schema.json`](schema/spec.schema.json).

### Required Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Short, human-readable task name (max 200 chars) |
| `goal` | string | Primary objective (max 5000 chars) |

### Optional Fields

| Field | Type | Description |
|---|---|---|
| `version` | string | Spec version (default: "0.1.0") |
| `background` | string | Context and motivation |
| `scope` | string | What is in scope |
| `non_goals` | string[] | What is explicitly out of scope |
| `relevant_systems` | string[] | Systems relevant to this task |
| `likely_files` | string[] | Files likely to be created/modified |
| `acceptance_criteria` | string[] | Verifiable completion conditions |
| `eval_requirements` | object[] | Eval hooks (description, check_type, params) |
| `risks` | object[] | Risks with risk, mitigation, severity |
| `dependencies` | string[] | Required dependencies |
| `review_expectations` | string[] | Review requirements |
| `human_approval_points` | string[] | Where human sign-off is needed |
| `estimated_effort` | string | Effort estimate (e.g., "3 days") |
| `priority` | string | critical / high / medium / low |
| `assignee` | string | Who is assigned |
| `tags` | string[] | Categorization tags |

## Agent Context Export

The `export-agent-context` command produces a structured prompt for AI agents:

```
## Task: Add user avatar upload

### Goal
Implement avatar upload endpoint for user profiles.

### Acceptance Criteria (Definition of Done)
Your work is complete ONLY when ALL of these are true:

1. POST returns 201 with avatar URL
2. Uploads >5MB return 413

### Priority
**high** priority

---
**Instructions:** Read context before starting. Understand goal and scope.
Verify acceptance criteria. Stop at approval points.
```

Use `--format dispatch` to export a Dispatch-compatible work unit summary.

## Integration Points

Spec is designed to integrate with the Kujo ecosystem:

- **kujo-eval** — eval requirements map to eval checks
- **kujo-dispatch** — specs export as dispatch work units
- **kujo-scout** — specs become scoutable work items
- **kujo-mcp** — agent tools can consume spec context

## Known Limitations

- YAML parsing: complex YAML features (anchors, multi-document, tags) are not supported. Use the subset documented above.
- TOML parsing: basic key=value only. Nested tables and arrays of tables are not yet supported.
- Kujo runtime: The `spec` CLI uses a shell script wrapper for YAML/TOML parsing. The Kujo validate/render/export modules use JSON internally. Cross-module imports (`from src.common import ...`) are supported as of Kujo v1.0.0+.
- The `KUJO_BIN` environment variable must point to the Kujo language runtime (not the Python linter).
- File size limit: 1MB maximum per spec file. Larger files are rejected before parsing.
- When `SPEC_SAFE_WRITE` is enabled, output paths are restricted to the current project root unless `--unsafe-write` is provided.
- `spec changelog` defaults to the latest tag when present and falls back to the repository root commit when no tags exist.

## Compatibility

| Component | Supported | Notes |
|---|---|---|
| Shell | Bash 3.2+ | macOS default Bash is supported |
| Kujo runtime | Kujo language runtime | Set `KUJO_BIN` if runtime is not on `PATH` |
| Python | Python 3.8+ | Required for YAML/TOML conversion helpers |
| YAML | `pyyaml` preferred | Fallback parser supports documented subset |
| TOML | stdlib `tomllib` or fallback parser | Nested tables are currently out of scope |

## Repository Root Files

This repository intentionally keeps several control files at the root. They are part of release and policy gates and should not be moved into `src/`:

- `VERSION`
- `RUNTIME_VERSION`
- `kennel.toml`
- `kujo.toml`

If you reorganize source code, keep these files in root unless release tooling is updated first.

## Benchmark Methodology

`tests/benchmark.sh` uses a stable, single-pass methodology:

- Generate `N` YAML specs with valid minimal content.
- Time one `spec validate-all` run over that directory.
- Compare wall-clock runtime to an environment budget.
- Enforce trend budget using `ci_runtime_ms` from machine-readable benchmark summary output.

Supported benchmark profiles:

| Profile | Default count | Default budget |
|---|---:|---:|
| `local` | 100 | 30s |
| `ci-linux` | 30 | 60s |
| `ci-macos` | 30 | 90s |
| `stress` | 300 | 120s |

Examples:

```bash
# Local developer baseline
bash tests/benchmark.sh

# CI Linux profile (same defaults used by release gates)
SPEC_BENCH_PROFILE=ci-linux bash tests/benchmark.sh

# Explicit override
bash tests/benchmark.sh 100 60 ci-linux
```

## Verification

```bash
# Pin Kujo runtime for deterministic local runs
export KUJO_BIN=/path/to/kujo/target/release/kujo

# Run test suite
bash tests/run_tests.sh

# Performance benchmark
bash tests/benchmark.sh

# Release quality gates
bash scripts/release_quality_gates.sh

# Supply chain policy check
bash scripts/supply_chain_policy_check.sh

# Doc command parity check
bash scripts/verify_docs_command_parity.sh

# Shell completion parity check
bash scripts/verify_completion_parity.sh

# Runtime parity check
bash scripts/verify_test_runtime_parity.sh
```

If `KUJO_BIN` is unset or points to the wrong binary, validation/render/export tests can fail with empty output.

## Enterprise References

- `docs/ENTERPRISE_USAGE_GUIDE.md`
- `docs/RELEASE_NOTES_TEMPLATE.md`

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Validation failure or usage error |

## License

MIT
