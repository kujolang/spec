# Sequential Spec CI performance

## Repository and baseline

- Repository `kujolang/spec`, branch `main`. Starting revision `8415d4992fd399a7ae8a9959c415058919944b4f`. Verified code revision `77ab2d4ead3518f5e07f2fe27b46e9ad946cce48`.
- Spec defines task contracts for people and agents. The Bash CLI discovers inputs and formats results. Python handles CI validation, and Kujo handles YAML and TOML conversion. Eval and Dispatch consume separate exports.
- The baseline code launched a Python interpreter for each JSON spec in sequential CI. The [earlier function audit](spec-function-performance-2026-11-25.md) measured that path on eight files. This audit compares the same command on larger inputs against the revision above.

## Findings

| ID | Priority | Area | Evidence | Action | Status |
| --- | --- | --- | --- | --- | --- |
| CI-01 | P1 | Sequential CI latency | The baseline called `validate-ci-json` for every JSON file. Discovery and validation run in order, so interpreter startup accumulates with file count. | Validate up to 256 consecutive JSON files per helper invocation. | Fixed |
| CI-02 | P2 | Batch resource limits | `validate-all` forwards source JSON directly to `validate_many`, which calls `json.load` without the documented 1 MB limit. | Track applying the source size ceiling before decoding in SignalBox. | Open |
| CI-03 | P1 | Packaging | The npm manifest omits the startup module `scripts/commands/maintenance.sh` in both revisions. Running `spec version` from the optimized npm package layout exits 1. The Homebrew formula and shell installer also omit the module in source. | Track installed CLI startup and packaging verification in SignalBox. | Open |

## Implementation and compatibility

`scripts/commands/maintenance.sh` batches consecutive JSON inputs while preserving sorted file order, mixed-format conversion, and `--max-files` selection. `scripts/spec_helpers.py` reuses the per-file validator and emits one status per processed JSON file. Under `--fail-fast`, the helper stops reading spec contents at the first failure. The CLI retains the existing exit codes, failure paths and text, JSON, and GitHub result formats. Explicit parallel scans retain their existing worker behavior. The batch uses NUL-delimited stdin to keep filenames separate and avoid argument-size limits at the helper boundary. Each file still passes the regular-file, project-path, and size checks before validation.

The regression test covers the batch boundary, strict warning handling, fail-fast, truncation, YAML and TOML, malformed JSON, and oversized JSON. Existing tests cover explicit parallel ordering and the public receipt formats. No new dependency, process-shared state, schema, config, or environment variable was introduced.

## Performance measurement

Both revisions ran on the same shared Intel macOS 26.6.2 host with Bash 3.2.57, Python 3.10.5 and Kujo 1.5.0. A fixture generator created 120 sorted JSON specs and 12 sorted YAML specs in separate directories. Every fixture had a name, goal, medium priority, and one tag. The paired runner alternated checkout order, discarded one warm-up per revision, and measured five runs per revision with Python's monotonic clock. It compared the exit status and both output streams byte for byte.

| Command | Baseline median (range) | Optimized median (range) |
| --- | ---: | ---: |
| `spec ci json --strict --format json` | 35.56 s (30.58–75.15) | 0.72 s (0.61–2.47) |
| `spec ci json --max-files 10 --format json` | 6.97 s (5.08–11.48) | 1.12 s (0.79–3.63) |
| `spec ci yaml --format json` (control) | 26.96 s (15.36–32.15) | 22.47 s (11.93–37.01) |

The 120-spec run used one validation helper invocation instead of 120. The median elapsed time was 98.0% lower. The YAML control had overlapping ranges and continued to use the existing conversion path. The ranges reflect varying host load. Peak memory, build size, and output token counts were outside the measurements. This path does not build an artifact or invoke a model.

## Audit coverage

| Checklist phases | Reviewed evidence and scope |
| --- | --- |
| 0–1 | CLI, helper, runtime converter, schema, fixtures, CI, and preceding audit established the relevant paths and baseline. |
| 2–4 | Repeated interpreter startup was the measured cost. Batches bound result buffering and the validator processes one spec at a time. |
| 5–7 | Stable failure receipts and early exit preserve agent feedback. Agent-context, Eval and Dispatch exports use separate paths. Model calls, replay, MCP registration and token measurements were outside this local CI change. |
| 8–10 | Existing project and symlink checks, regular-file and size checks, deterministic order, and CLI contracts were reviewed. Advisory CI-02 concerns the separate `validate-all` path. |
| 11–13 | No dependencies changed. Regression coverage checks observable results and existing benchmark budgets still apply. Timing thresholds specific to sequential CI were avoided because interpreter startup varies across hosts. |
| 14–16 | The architecture now describes JSON batching. Runtime setup, command discovery, exit behavior, and machine-readable output follow the existing contract. This pass found no relevant dead code that warranted removal. |

No cross-repository changes are required. SignalBox tracks the size limit under Capture `cap_70bc540f-f49f-4f66-a7d7-2470467e279d` and Signal `sig_f5e6a1ae-6f5e-4cc7-ac15-d50667d3100d`. It tracks the packaging issue under Capture `cap_7f967253-20c4-44a7-9176-eedcb3577c2c` and Signal `sig_cd65be8f-b1a2-4127-be54-f073d8f4dc61`.

## Verification

| Command | Baseline | Optimized |
| --- | --- | --- |
| `bash tests/run_tests.sh` | 109 passed | 110 passed |
| `bash scripts/verify_docs_command_parity.sh` | 31 passed | 31 passed |
| `bash scripts/verify_completion_parity.sh` | 132 passed | 132 passed |
| `bash scripts/verify_test_runtime_parity.sh` | 3 passed | 3 passed |
| `bash scripts/supply_chain_policy_check.sh` | 13 passed | 13 passed |
| `bash tests/benchmark.sh` | 100/100 in 2.76 s | 100/100 in 4.21 s |
| `bash scripts/release_quality_gates.sh` | 20 passed | 20 passed |
| `bash -n scripts/commands/maintenance.sh` and `bash -n tests/run_tests.sh` | Starting files | Passed |
| `git diff --check 8415d49` | Starting tree clean | Passed |
| `npm pack --dry-run --ignore-scripts --json` and package-layout smoke check | Manifest omits startup module | Same manifest gap. Packaged `spec version` exits 1. |

The repository's standalone benchmark exercises `validate-all`. Both runs passed its 30-second budget. The single measurements reflect shared host load. The paired times above apply to `spec ci`.
