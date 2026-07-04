# Contributing

Thanks for helping improve this Kujo ecosystem project.

This guide is intended for standalone Kujo tools and primitives. It does not
cover the core Kujo language repo, Kujo Skills, or Kujo Workflows when those
projects have their own contribution rules.

## Development Principles

- Keep changes focused, reviewable, and tied to one user-visible concern.
- Prefer deterministic, local-first behavior.
- Do not add network calls, provider calls, timestamps, or machine-specific
  output to core command paths unless the feature explicitly requires it.
- Preserve redaction, path safety, guarded cleanup, and stable output ordering.
- Add tests for behavior changes. Bug fixes should include regression coverage.
- Avoid speculative refactors unless they directly simplify the change at hand.

For Spec specifically, preserve exact JSON field names, stdout/stderr behavior,
safe-write semantics, template-source policy, command inventory parity, and
completion parity unless the task explicitly changes a contract.

## Local Setup

Use the Kujo runtime expected by this repository. Most repos support one of
these environment variables:

```bash
export KUJO_BIN=/path/to/kujo
export KUJO=/path/to/kujo
```

Spec setup:

```bash
git clone https://github.com/kujolang/spec.git
cd spec
export KUJO_BIN=/path/to/kujo/target/release/kujo
export PATH="$PWD/scripts:$PATH"
```

Set `KUJO_BIN` to the Kujo language runtime, not Python's unrelated `kujo`
linter.

Project layout:

```text
kujo-spec/
  scripts/spec          Main CLI entry point
  scripts/commands/     Modular shell command handlers sourced by scripts/spec
  src/                  Kujo modules: validate, render, export, common
  tests/                Test scripts and shared helpers
  schema/               JSON Schema
  fixtures/             Valid and invalid test fixtures
  examples/             Example spec files
  docs/                 Documentation
  completions/          Shell completions
```

Check the repo README, `Makefile`, `tests/`, and `scripts/` directory for the
authoritative local commands.

## Agent And Example Hygiene

Start with `README.md`, `CONTRIBUTING.md`, relevant docs, and examples before
broad source sweeps.

Treat user-facing examples as canonical copyable surfaces. Examples should be
short, runnable, and representative of the idioms humans and agents should copy.

For Spec:

- Start with `README.md`, this file, and `docs/PROJECT_STRUCTURE.md`.
- Treat `examples/` as canonical copyable examples.
- Treat `fixtures/` as test data; do not shorten fixtures when explicit shape
  helps a test.
- Treat `docs/COMMAND_INVENTORY.md` as generated from `scripts/spec help`.
- Treat `docs/IMPROVEMENT_CHECKLIST.md`, `docs/READINESS_REVIEW.md`, and
  `docs/codex-*.md` as generated or review artifacts unless the task targets
  them directly.

Exclude generated and bulk paths from broad searches unless the task explicitly
targets them:

```bash
rg -n "pattern" README.md CONTRIBUTING.md docs src scripts examples tests \
  -g '!docs/COMMAND_INVENTORY.md'
```

Document any important search exclusions in larger cleanup or audit PRs.

## Code Standards

- Match the surrounding code style before introducing a new abstraction.
- Keep command output readable and stable.
- Prefer small local helpers for repeated output, error, section, or key/value
  formatting once repetition distracts from the behavior.
- Keep CLI contracts explicit: flags, exit codes, JSON fields, artifact paths,
  and documented examples should agree with parser behavior.
- Keep config honest. A config key should either change observable behavior or
  be clearly documented as reserved.
- Preserve compatibility entrypoints and wrappers when a repo provides them.
- Shell scripts use Bash, `set -euo pipefail`, and shared helpers from
  `tests/test_helpers.sh`.
- Kujo modules use tabs for indentation, shared helpers imported from
  `src.common`, and direct examples before helper-heavy output.
- Python uses type hints, `sys.argv` for file paths, and `yaml.safe_load()`.
- Tests use `check()`, `check_output()`, and `check_fail()` from
  `tests/test_helpers.sh`.

## Kujo Runtime Notes

Kujo ecosystem tools often follow these defensive patterns:

- Prefer `while` loops in complex functions.
- Avoid duplicate local names across branches in the same function.
- Keep imports at the top of the file.
- Export functions that are imported by another module.
- Guard dictionary access with `has_key()` or local helper wrappers.
- Remember that some builtins return int-like `1`/`0` instead of booleans.
- Guard parsing operations such as JSON or TOML parsing and validate the result.
- Keep deep tree walks iterative where recursion risks VM stack limits.
- Be careful with byte-based string indexes versus character-based substring
  operations; use existing repo helpers when available.

Spec-specific runtime notes:

- Kujo modules use `from src.common import ...`; run from the repository root so
  module resolution remains stable.
- Cross-repo imports are intentionally unsupported by runtime safety checks.
- Use `has_key()` rather than `type()` for dictionary key checks.
- `parse_json()` and `to_json()` are available builtins.

## Validation

Before opening a pull request, run the strongest local validation available for
the repo.

Spec validation:

```bash
bash tests/run_tests.sh
```

Full verification before committing:

```bash
export KUJO_BIN=/path/to/kujo/target/release/kujo
bash scripts/release_quality_gates.sh
bash scripts/supply_chain_policy_check.sh
bash scripts/verify_docs_command_parity.sh
bash scripts/verify_completion_parity.sh
bash scripts/verify_test_runtime_parity.sh
```

For large repositories, use CI scan controls during local verification:

```bash
scripts/spec ci <dir> --max-files <n>
scripts/spec ci <dir> --fail-fast
scripts/spec ci <dir> --jobs <n>
```

For regulated environments, enforce template provenance:

```bash
SPEC_TEMPLATE_SOURCE_POLICY=project-only
scripts/spec init --strict-template-source --from template:<name> ...
```

Tests should stay offline and deterministic unless the repo explicitly marks a
live-provider or network test as opt-in.

## Documentation And Changelog

Update docs when behavior, configuration, command output, flags, schemas,
examples, or security expectations change.

For Spec command-surface changes, regenerate or update:

- `README.md`
- `docs/API_REFERENCE.md`
- `docs/COMMAND_INVENTORY.md`
- `docs/ARCHITECTURE.md`
- `docs/INTEGRATION_GUIDE.md`
- `docs/ENTERPRISE_USAGE_GUIDE.md`
- `completions/spec.{bash,zsh,fish}`
- `schema/spec.schema.json`
- examples
- `CHANGELOG.md`

Root-level release and policy files are intentionally kept at repository root:

- `VERSION`
- `RUNTIME_VERSION`
- `kennel.toml`
- `kujo.toml`

Do not move these into `src/` without updating release and policy scripts first.

User-visible behavior changes should include a changelog entry when the repo has
a changelog.

## Pull Requests

A good PR includes:

- Problem statement.
- Change summary.
- User-visible impact.
- Test evidence with commands and outcomes.
- Documentation or changelog updates.
- Known risks or follow-up work, if any.

Keep generated artifacts out of commits unless the artifact is the reviewed
output of the change.

Commit format:

```text
spec(<ITEM_ID>): <summary>
```
