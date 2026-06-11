# Next Session Enterprise Checklist

This checklist captures the highest-value follow-up work after the current hardening pass.

## 1. Reliability and Scale

- [x] Add optional parallel validation mode for `spec ci` in very large repositories.
Implementation expectations:
Introduce a bounded worker model (configurable concurrency), preserve deterministic output ordering, and keep default behavior backward-compatible.
Acceptance criteria:
`spec ci --format json` preserves contract fields, supports deterministic ordering, and completes faster than sequential mode on a synthetic large fixture set.
Validation/testing expectations:
Add tests covering mixed pass/fail sets, fail-fast with parallel mode, and stable JSON summaries.
Dependencies/unknowns:
Need a Bash 3.2-compatible implementation strategy.

Status update:
Implemented with `spec ci --jobs <n>` plus deterministic summary ordering and regression coverage.

- [x] Add benchmark trend guard for `spec ci` runtime.
Implementation expectations:
Extend benchmark script to emit machine-readable `ci_runtime_ms` and compare against profile budgets in CI.
Acceptance criteria:
Release gate fails when runtime regresses above threshold for selected profile.
Validation/testing expectations:
Run benchmark profiles (`local`, `ci-linux`, `ci-macos`) and verify threshold enforcement behavior.
Dependencies/unknowns:
Requires baseline calibration for CI runner variability.

Status update:
Implemented in `tests/benchmark.sh` with machine-readable `ci_runtime_ms` output and profile budget enforcement via `tests/benchmark_trend_budgets.json`.

## 2. Security Hardening

- [x] Add optional strict mode for templates sourced from user home.
Implementation expectations:
Provide a flag/env guard to allow only project templates unless explicitly enabled.
Acceptance criteria:
Template initialization fails with clear messaging when user templates are blocked by policy.
Validation/testing expectations:
Add tests for policy on/off behavior and error messaging.
Dependencies/unknowns:
Define default policy that balances DX and security expectations.

Status update:
Implemented with `spec init --strict-template-source` and env policy `SPEC_TEMPLATE_SOURCE_POLICY=allow-home|project-only`.

- [x] Add schema lint gate for unknown top-level fields in non-strict mode.
Implementation expectations:
Emit warnings in normal validation, hard-fail under strict mode.
Acceptance criteria:
Unknown top-level keys are consistently surfaced across JSON/YAML/TOML inputs.
Validation/testing expectations:
Add fixtures for unknown key cases and assert warning/error behavior.
Dependencies/unknowns:
Confirm contract compatibility for existing downstream consumers.

Status update:
Validator now emits warnings for unknown top-level fields; `--strict` promotes these warnings to failure.

## 3. Functionality and Ecosystem

- [x] Expand `spec export` with machine-consumable metadata envelope option.
Implementation expectations:
Add a format variant that includes source file, schema version, and checksum metadata alongside exported payload.
Acceptance criteria:
Exported output includes stable metadata fields and round-trips in automation pipelines.
Validation/testing expectations:
Add format-specific contract tests and docs parity checks.
Dependencies/unknowns:
Choose naming to avoid collisions with existing export formats.

Status update:
Implemented as `spec export --format envelope` with `metadata` (`source_file`, `schema_version`, `checksum_sha256`, `generated_at`, `payload_format`) and payload support for `agent` or `dispatch`.

- [x] Add shell completion coverage tests for key command flags.
Implementation expectations:
Verify completion scripts include new options (`--max-files`, `--fail-fast`) and key subcommands.
Acceptance criteria:
Completion scripts stay in sync with help output.
Validation/testing expectations:
Add a parity check script for completion keyword coverage.
Dependencies/unknowns:
Need to define shell-specific test approach for bash/zsh.

Status update:
Added `scripts/verify_completion_parity.sh` plus test and release-gate coverage; bash/zsh/fish completion files now include key enterprise flags.

## 4. Documentation and Adoption

- [x] Publish an enterprise usage guide for monorepos and regulated environments.
Implementation expectations:
Add a focused doc with policy examples, CI snippets, and migration paths from ad-hoc task specs.
Acceptance criteria:
Guide includes at least one end-to-end example from spec authoring to CI enforcement.
Validation/testing expectations:
Run docs parity plus command examples validation.
Dependencies/unknowns:
Coordinate examples with real-world internal repository layouts.

Status update:
Published `docs/ENTERPRISE_USAGE_GUIDE.md` including monorepo layout guidance, regulated workflow controls, and an end-to-end CI enforcement example.

- [x] Add a release notes template for spec CLI capability changes.
Implementation expectations:
Standardize a changelog entry structure for security/performance/functionality improvements.
Acceptance criteria:
Release workflow references template and generated notes remain consistent.
Validation/testing expectations:
Dry-run release workflow and confirm notes generation path.
Dependencies/unknowns:
Align with existing project changelog conventions.

Status update:
Published `docs/RELEASE_NOTES_TEMPLATE.md` and referenced it from release workflow guidance in `scripts/release.sh`.

## Notes from Current Session

- Root-level control files are intentionally required and should remain in root: `VERSION`, `RUNTIME_VERSION`, `kennel.toml`, `kujo.toml`.
- New CI options and template list fixes were added; next work should build on those foundations, not rework them.
