# Next Session Enterprise Checklist - 2026-06-19

This checklist captures follow-up work after the latest robustness pass. Work from top to bottom unless an item is explicitly blocked. Each completed item should include tests, docs updates when user-facing behavior changes, and verification evidence.

## Current State

Spec is substantially production-oriented: it has a split `src/` module layout, a Bash CLI wrapper, generated command inventory, shell completions, safe-write controls, path and symlink boundary checks, strict validation mode, fuzz tests, benchmark gates, and release quality gates.

It should still be validated in each enterprise environment before being called universally production-ready. The biggest remaining gains are deeper contract validation, packaged distribution verification, and more scalable internals.

## 1. Security and Trust Boundaries

- [ ] Add safe output writes for `spec status --set`.
Implementation expectations:
`status --set` mutates the input file in place. Add explicit policy documentation and confirm the command cannot follow a writable symlink outside the project during backup/restore/update.
Acceptance criteria:
Outside-project symlink targets are rejected before backup creation, and in-project status updates still pass.
Verification:
Add tests for in-project symlink success and outside-project symlink failure.

- [ ] Add template provenance metadata to `spec init --from template:*`.
Implementation expectations:
When a spec is initialized from a template, optionally record source kind (`project` or `home`) and template name in a warning or metadata envelope without changing the spec schema by default.
Acceptance criteria:
Users can audit whether a generated spec came from project-controlled templates or user-home templates.
Verification:
Add CLI tests for project template and home template provenance output.

## 2. Contract and Schema Depth

- [ ] Strengthen array item type validation.
Implementation expectations:
Validate that string-array fields contain strings only, and object-array fields contain objects only.
Acceptance criteria:
`tags: [1]`, `dependencies: [123]`, and malformed `risks`/`eval_requirements` entries fail clearly.
Verification:
Add JSON/YAML fixtures and strict/non-strict tests.

- [ ] Align `schema/spec.schema.json` and runtime validation one-to-one.
Implementation expectations:
Create a parity test that compares documented schema fields/enums against `src/validate.kujo` constants.
Acceptance criteria:
Adding a field or enum in one place fails tests unless the other is updated.
Verification:
Add a script under `scripts/` and wire it into release quality gates.

## 3. Performance and Scale

- [ ] Add a synthetic large-repo benchmark fixture generator.
Implementation expectations:
Generate nested spec trees with configurable depth, format mix, invalid-file ratio, and duplicate names.
Acceptance criteria:
Benchmark can simulate small project, monorepo, and stress profiles without hand-maintained fixtures.
Verification:
Extend `tests/benchmark.sh` or add a focused script with machine-readable output.

- [ ] Evaluate replacing per-file Kujo process startup in `spec ci`.
Implementation expectations:
Prototype a batch validation path that converts files once and validates many JSON specs in fewer runtime invocations.
Acceptance criteria:
Runtime improves on 100+ specs while preserving identical JSON/text/GitHub output contracts.
Verification:
Compare before/after benchmark summaries and retain deterministic ordering.

## 4. Distribution and Adoption

- [ ] Validate install surfaces end to end.
Implementation expectations:
Exercise local install, Homebrew formula syntax, Docker build where Docker is available, and packaged script execution from outside the repo checkout.
Acceptance criteria:
Install docs match verified behavior and failures are documented as environment blockers, not silent assumptions.
Verification:
Capture command evidence in `docs/RELEASE_SIGNOFF.md`.

- [ ] Add a short guided tutorial for first-time Kujo users.
Implementation expectations:
Show how Spec demonstrates Kujo language strengths: schema-shaped contracts, render/export modules, CI automation, and local-first trust controls.
Acceptance criteria:
New users can create, validate, render, export, and run CI on a spec in under 10 minutes.
Verification:
Run docs command parity on every command in the tutorial.

## 5. Presentation Quality

- [ ] Refresh README examples with one cohesive real-world workflow.
Implementation expectations:
Replace scattered examples with a single task flowing from authoring to render, agent export, eval export, and CI.
Acceptance criteria:
The README reads like a polished product entry point and still remains accurate to the CLI.
Verification:
`bash scripts/verify_docs_command_parity.sh` passes after update.

- [ ] Add command screenshots or rendered artifacts for marketing/docs reuse.
Implementation expectations:
Generate Markdown render examples and JSON envelope snippets from stable fixtures.
Acceptance criteria:
Docs can show real output without hand-written drift.
Verification:
Regenerate artifacts from fixtures and add a parity check if outputs are checked in.
