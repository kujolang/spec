# Changelog

## [Unreleased]

- Hardened interactive YAML creation and graph-label escaping for untrusted spec content.
- Made render and export commands fail clearly when the Kujo runtime fails or emits no output.
- Aligned fast batch validation with schema limits and eliminated false-success exit-code wrapping.
- Batched `validate-all` path checks, reducing the 100-file local benchmark from 39.82s to 0.92s on the audited host.
- Isolated conversion caches by user and rejected symlink cache directories.
- Required SHA-256 verification when Docker builds download a Kujo runtime binary.
- Installed the pinned Kujo v1.1.0 release in hosted Linux/macOS CI from repository-owned checksums.

## [1.0.0] - 2026-08-08

- Declared the task-contract schema, CLI, safe-write controls, and export formats stable.
- Aligned package, launcher, installer, formula, and contract version metadata at 1.0.0.
- Retained strict validation, path-boundary, completion-parity, benchmark, and release-quality gates.
