# Spec v0.1.0 — Release Sign-off Checklist

Snapshot date: 2026-05-26

This checklist reflects fresh verification evidence and the current release process contract.

## Release Information

| Field | Value |
|---|---|
| Version | 0.1.0 |
| Release date target | 2026-05-26 |
| Owner | Robert DeVore |
| Repository | github.com/kujolang/spec |

## Verification Summary

- [x] Test suite passes (`66/66`)
- [x] Release quality gates pass (`19/19` with configured benchmark/fuzz budgets)
- [x] Supply chain policy passes (`10/10`)
- [x] Doc parity passes (`26/26`)
- [x] Runtime parity passes (`3/3`)
- [x] Benchmarks pass target budgets (`30<=30s`, `100<=60s` in `ci-linux` profile)

## Documentation and Contract Coverage

- [x] README updated for runtime assumptions, compatibility, and benchmark methodology
- [x] API reference aligned to generated command inventory source
- [x] Architecture docs updated for modular CLI + shared Kujo imports
- [x] Readiness review regenerated with current evidence
- [x] Command inventory generated from `spec help` and parity-checked

## CI and Portability Coverage

- [x] CI matrix includes Linux + macOS
- [x] CI includes command-surface smoke checks
- [x] CI includes packaging checks (installer smoke + Homebrew formula syntax when Ruby is available)
- [x] Benchmark profile/budget is environment-aware in CI

## Release Artifact and Provenance Policy

- [x] Release artifact policy documented: `docs/RELEASE_ARTIFACT_POLICY.md`
- [x] `scripts/release.sh` defines deterministic artifact generation for:
	- `dist/kujo-spec-vX.Y.Z.tar.gz`
	- `dist/kujo-spec-vX.Y.Z.sha256`
	- `dist/kujo-spec-vX.Y.Z.provenance.json`
- [x] Homebrew formula notes reference artifact provenance policy before pinned tarball+SHA publication

## Signatures

| Role | Name | Date | Status |
|---|---|---|---|
| Author | Robert DeVore | 2026-05-26 | ✅ Signed |
| Reviewer | — | — | Pending |
| Security | — | — | Pending |
| Release Manager | — | — | Pending |

## Known Constraints

1. YAML support intentionally targets a documented subset (no anchors/tags/multi-doc).
2. TOML support intentionally targets simple key/value structures.
3. CI/runtime environments must provide the Kujo language runtime binary (`KUJO_BIN`).
