# Repository Hardening Audit

Audit date: 2026-08-30

## Repository

- Repository: `kujolang/spec`
- Branch: `main`
- Starting SHA: `d5103347e83289634a6e6423007f8fe52ea24759`
- Ending implementation SHA: `35159756626525bf3bc2d79bacc10e09f5695dd0` (the audit-report commit follows this implementation commit)
- Purpose: define, validate, render, discover, and export Kujo task contracts.
- Important integrations: Kujo runtime, Kujo Eval export, Dispatch envelopes, Scout discovery, MCP consumers, Kennel packaging, Homebrew/npm installers, and GitHub Actions.

## Baseline

The starting tree passed 97 CLI tests, 31 documentation command checks, 132 completion checks, three runtime-parity checks, 20 release gates, and 10 supply-chain checks. The default local benchmark failed: validating 100 JSON specs took 39.82 seconds (398.2 ms/spec) against a 30-second budget. No dependency vulnerabilities were reported because the npm package has no runtime dependencies.

The untracked user file `_test_schema_fields.json` existed before the audit and was not modified or committed.

## Findings

| ID | Priority | Area | Finding | Evidence | Action | Status |
| -- | -------- | ---- | ------- | -------- | ------ | ------ |
| PERF-01 | P1 | Runtime | `validate-all` launched path-resolution helpers for every discovered file. | 100-file baseline: 39.82s. | Validate the requested directory boundary once and batch JSON validation. | Fixed |
| REL-01 | P1 | Errors | Render and export swallowed Kujo runtime failures and could return success with empty output. | `|| true` followed runtime calls. | Fail closed on runtime error or empty output. | Fixed |
| CONTRACT-01 | P1 | Validation | Fast validation omitted schema constraints and could crash on malformed nested values. | `parent_id`, empty acceptance criteria, nested eval types, and length limits were unchecked. | Align Kujo and Python validators and add regression cases. | Fixed |
| CONTRACT-02 | P1 | Exit codes | Returning a raw failure count made 256 failures wrap to exit status 0. | Shell exit statuses are modulo 256. | Return boolean success/failure from batch commands. | Fixed |
| SEC-01 | P1 | Input | Interactive values were interpolated directly into YAML. | Quotes, comments, and YAML syntax could alter the generated document. | Validate names and serialize values as data. | Fixed |
| SEC-02 | P1 | Output | Untrusted names were embedded unescaped in Mermaid and DOT labels. | Quotes/newlines could inject graph statements. | JSON-escape graph labels. | Fixed |
| SEC-03 | P1 | Supply chain | Docker runtime downloads were not integrity checked. | `wget` output was made executable directly. | Require and verify `KUJO_BIN_SHA256`. | Fixed |
| SEC-04 | P2 | Filesystem | Conversion caching used a predictable shared fallback path. | `${TMPDIR:-/tmp}/.spec_cache`. | Use a private per-user directory and reject symlink cache paths. | Fixed |
| REL-02 | P2 | Configuration | Invalid `SPEC_TIMEOUT` values reached process wrappers unchecked. | Environment value was passed to `timeout`/Perl alarm. | Require a positive integer at startup. | Fixed |
| DOC-01 | P2 | Documentation | Architecture and security docs still described retired Python conversion paths. | CLI uses `src/convert.kujo`; docs said PyYAML/TOML helpers. | Correct requirements, architecture, security, and ADR status. | Fixed |
| CI-01 | P1 | CI | The workflow named `kujo` but did not install it. | `.github/workflows/ci.yml` only wrote `KUJO_BIN=kujo`; no runs were available through `gh run list`. | Install Kujo v1.1.0 release archives using repository-owned platform checksums. | Fixed |

## Changes Implemented

### Batch validation performance and correctness

The repeated path-safety subprocesses in `validate-all` were removed after moving the same project-boundary check to the requested directory. JSON inputs continue to be processed in one validation helper invocation. Validation now covers schema string/item limits, `parent_id`, non-empty acceptance criteria, nested eval objects, and malformed priority values. Batch commands return a boolean status rather than a raw count. Regression tests cover the new constraints and the 256-failure boundary.

Files: `scripts/spec`, `scripts/spec_helpers.py`, `src/validate.kujo`, `tests/run_tests.sh`.

Compatibility: valid specs and JSON output field names are unchanged. Inputs that violated the published schema but previously slipped through fast validation now fail as documented.

### Runtime and generated-output hardening

Render, agent/dispatch export, and envelope export now surface Kujo runtime failure and empty output. Export formats are validated before dispatch. Interactive creation validates required fields and safely serializes YAML. Graph generators escape untrusted labels. Timeout configuration and cache paths are validated.

Files: `scripts/spec`, `scripts/commands/maintenance.sh`, `tests/run_tests.sh`, `SECURITY.md`.

Compatibility: successful command output and supported formats are unchanged. Previously silent runtime failures now return exit 1 with actionable errors.

### Supply-chain and documentation alignment

Docker runtime downloads now require a SHA-256 and the supply-chain gate locks this in. Documentation now reflects Kujo-native YAML/TOML conversion and Python's actual CLI-support role; ADR-004 is marked superseded without deleting the historical decision.

Files: `Dockerfile`, `scripts/supply_chain_policy_check.sh`, `README.md`, `docs/ARCHITECTURE.md`, `docs/adr/*`, `CHANGELOG.md`.

### Hosted CI runtime provisioning

Linux x64, macOS x64, and macOS arm64 runners now download the explicit Kujo v1.1.0 release archive, verify it against repository-owned SHA-256 values, reject unexpected archive paths, verify the installed version, and export `KUJO_BIN`/`PATH` for later steps. The installer rejects versions absent from the checksum manifest before making a network request.

Files: `.github/workflows/ci.yml`, `.github/scripts/install-kujo-runtime.sh`, `.github/kujo-runtime-checksums.txt`, `scripts/supply_chain_policy_check.sh`.

Hosted verification also exposed two portability assumptions: macOS tests used the non-default `timeout` command and imported optional PyYAML, while packaging expected `INSTALL_DIR` to exist. Tests now use Spec's own timeout/conversion contracts and the installer creates its destination safely.

## Performance & Efficiency

| Measurement | Before | After | Delta |
| -- | --: | --: | --: |
| 100 JSON specs, `spec validate-all` | 39.82s | 0.92s | 38.90s faster (97.7%) |
| Per spec | 398.2ms | 9.2ms | 389.0ms lower |
| Local benchmark budget | Failed 30s | Passed 30s | Gate restored |

The benchmark measures validation only; spec generation is intentionally outside the timer. No memory, binary-size, or model-token claim was made because those dimensions are not material to this local CLI change and no representative measurement existed.

## Security

Reviewed boundaries included CLI arguments, file/directory paths, symlinks, output paths, temp/cache storage, YAML/TOML/JSON input, interactive input, graph output, subprocess arguments/timeouts, Docker downloads, template sources, and generated agent/dispatch payloads. Fixes cover unsafe YAML interpolation, graph injection, cache isolation, timeout validation, fail-closed runtime handling, and downloaded-binary verification. Regression tests exercise each repository-controlled boundary.

Remaining concern: Spec executes the Kujo runtime with the caller's permissions; runtime sandboxing remains outside this repository's control.

## Compatibility

- Public APIs: no field or function removals.
- CLI: successful output is unchanged; invalid formats/configuration and runtime failures now fail deterministically.
- File formats and schemas: no schema file change. Runtime enforcement is stricter where it previously diverged from the existing schema.
- Configuration: `SPEC_TIMEOUT` must now be a positive integer. Docker builds using `KUJO_BIN_URL` must add `KUJO_BIN_SHA256`.
- Environment variables: no names added or removed from the CLI.
- External consumers: only consumers relying on undocumented acceptance of schema-invalid specs or silent empty exports should be affected.

## Cross-Repository Follow-Ups

None. The Kujo repository already publishes platform archives and checksums; Spec now consumes those v1.1.0 assets without requiring a sibling-repository change.

## Remaining Work

- P0: none.
- P1: none identified within repository scope.
- P2: none left with sufficient evidence.
- P3: formatting/style churn was intentionally skipped.
- Needs more evidence: removal of packaged legacy Python parser scripts, which may have downstream consumers.
- Not worth changing: micro-optimizing graph generation, which is not a measured hot path.

## Verification Receipt

| Command | Result |
| -- | -- |
| `bash tests/run_tests.sh` | PASS — 108 passed, 0 failed |
| `bash tests/benchmark.sh` | PASS — 100/100, 0.92s, 9.2ms/spec |
| `bash scripts/verify_docs_command_parity.sh` | PASS — 31 passed, 0 failed |
| `bash scripts/verify_completion_parity.sh` | PASS — 132 passed, 0 failed |
| `bash scripts/verify_test_runtime_parity.sh` | PASS — 3 passed, 0 failed |
| `bash scripts/release_quality_gates.sh` | PASS — 20 passed, 0 failed |
| `bash scripts/supply_chain_policy_check.sh` | PASS — 13 passed, 0 failed |
| `bash -n scripts/spec scripts/commands/maintenance.sh tests/*.sh scripts/*.sh` | PASS |
| `python3 -m compileall -q scripts` | PASS |
| `git diff --check` | PASS |

Verbose logs were retained under `/tmp/spec-final-*.log` for this audit session and are not repository artifacts.
