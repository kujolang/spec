# Spec v0.1.0 — Readiness Review

Snapshot date: 2026-05-26

All evidence below was rerun from the current working tree with:

```bash
export KUJO_BIN=/path/to/kujo/target/release/kujo
```

## Evidence Table

| # | Claim | Command | Exit Code | Signal | Note |
|---|---|---|---|---|---|
| 1 | Test suite passes | `bash tests/run_tests.sh` | 0 | PASS | 66 passed, 0 failed |
| 2 | Release quality gates pass | `SPEC_BENCH_COUNT=30 SPEC_BENCH_BASELINE_SECONDS=60 SPEC_BENCH_PROFILE=ci-linux SPEC_FUZZ_ITERATIONS=60 bash scripts/release_quality_gates.sh` | 0 | PASS | 19 passed, 0 failed |
| 3 | Supply chain policy passes | `bash scripts/supply_chain_policy_check.sh` | 0 | PASS | 10 passed, 0 failed |
| 4 | Doc parity passes | `bash scripts/verify_docs_command_parity.sh` | 0 | PASS | 26 passed, 0 failed |
| 5 | Runtime parity passes | `bash scripts/verify_test_runtime_parity.sh` | 0 | PASS | 3 passed, 0 failed |
| 6 | Benchmark 30-spec budget | `bash tests/benchmark.sh 30 30 ci-linux` | 0 | PASS | 30/30 validated in 16.39s |
| 7 | Benchmark 100-spec budget | `bash tests/benchmark.sh 100 60 ci-linux` | 0 | PASS | 100/100 validated in 56.58s |
| 8 | Changelog works in untagged repo | Included in `tests/run_tests.sh` | 0 | PASS | Fallback to root commit verified |

## Current Command Surface

Authoritative source:

- `docs/COMMAND_INVENTORY.md` (generated from `scripts/spec help`)

Regeneration command:

```bash
bash scripts/generate_command_inventory.sh write
```

## Compatibility Summary

- Bash 3.2+ (macOS default shell supported)
- Kujo runtime binary required via `KUJO_BIN`
- Python 3.8+ for YAML/TOML conversion helpers
- YAML/TOML support is subset-based (documented in README)

## Residual Risks

1. YAML parser behavior still targets a documented subset; advanced YAML features remain unsupported.
2. TOML parser behavior remains focused on simple key/value structures.
3. CI runners must provide the Kujo language runtime, not the Python Kujo linter binary.

## Review Sign-off

| Role | Name | Date | Signature |
|---|---|---|---|
| Author | Robert DeVore | 2026-05-26 | ✅ |
| Reviewer | — | — | — |
| Security | — | — | — |
| Release | — | — | — |
