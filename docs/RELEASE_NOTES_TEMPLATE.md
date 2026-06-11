# Spec Release Notes Template

Use this template for each release to keep enterprise change communication consistent.

## Release Metadata

- Version: vX.Y.Z
- Release date (UTC): YYYY-MM-DD
- Commit/tag: <sha or tag>
- Prepared by: <name/team>

## Summary

One paragraph describing what changed and why it matters.

## Security

- Change:
- Risk addressed:
- Operator impact:

## Performance

- Change:
- Benchmark/trend evidence:
- Runtime impact:

## Functionality

- Change:
- User-facing behavior:
- Backward compatibility notes:

## Reliability and Quality Gates

- `bash tests/run_tests.sh`: PASS/FAIL
- `bash scripts/verify_docs_command_parity.sh`: PASS/FAIL
- `bash scripts/verify_completion_parity.sh`: PASS/FAIL
- `bash scripts/verify_test_runtime_parity.sh`: PASS/FAIL
- `bash scripts/release_quality_gates.sh`: PASS/FAIL
- `bash scripts/supply_chain_policy_check.sh`: PASS/FAIL

## Documentation Updates

- Updated docs:
- Migration guidance:
- Known limitations:

## Compliance and Audit Evidence

- Benchmark summary artifact:
- Provenance artifact:
- Command inventory revision:

## Follow-up Items

- [ ]
- [ ]
- [ ]
