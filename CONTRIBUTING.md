# Contributing to Spec

## Setup

```bash
git clone https://github.com/kujolang/spec.git
cd spec
export KUJO_BIN=/path/to/kujo/target/release/kujo
export PATH="$PWD/scripts:$PATH"
```

## Development Workflow

1. Make changes to source files in `src/` or `scripts/`
2. Run tests: `bash tests/run_tests.sh`
3. Run full verification before committing:
   ```bash
   export KUJO_BIN=/path/to/kujo/target/release/kujo
   bash scripts/release_quality_gates.sh
   bash scripts/supply_chain_policy_check.sh
   bash scripts/verify_docs_command_parity.sh
   bash scripts/verify_completion_parity.sh
   bash scripts/verify_test_runtime_parity.sh
   ```
4. Commit with format: `spec(<ITEM_ID>): <summary>`

For large repositories, use CI scan controls during local verification:
- `scripts/spec ci <dir> --max-files <n>` to cap scan size
- `scripts/spec ci <dir> --fail-fast` to stop on first failure
- `scripts/spec ci <dir> --jobs <n>` to run deterministic parallel validation

For regulated environments, enforce template provenance:
- `SPEC_TEMPLATE_SOURCE_POLICY=project-only` to block home template sources in CI
- `scripts/spec init --strict-template-source --from template:<name> ...` for one-off strict resolution

## Code Conventions

- **Shell scripts**: bash, `set -euo pipefail`, source shared helpers from `tests/test_helpers.sh`
- **Kujo modules**: tabs for indentation, `has_key()` pattern for dict access, shared helpers imported from `src.common`
- **Python**: type hints, `sys.argv` for file paths (never string interpolation), `yaml.safe_load()`
- **Tests**: use `check()`, `check_output()`, `check_fail()` from `tests/test_helpers.sh`

## Project Structure

```
kujo-spec/
├── scripts/spec          # Main CLI entry point
├── scripts/commands/     # Modular shell command handlers sourced by scripts/spec
├── src/                  # Kujo modules (validate, render, export, common)
├── tests/                # Test scripts and shared helpers
├── schema/               # JSON Schema
├── fixtures/             # Test fixtures (valid/invalid specs)
├── examples/             # Example spec files
├── docs/                 # Documentation
└── completions/          # Shell completions
```

Root-level release and policy files are intentionally kept at repository root:
- `VERSION`
- `RUNTIME_VERSION`
- `kennel.toml`
- `kujo.toml`

Do not move these into `src/` without updating release/policy scripts first.

## Kujo Runtime Notes

- Set `KUJO_BIN` to the Kujo language runtime (not the Python linter)
- Kujo modules in this repo use `from src.common import ...`; run from repository root so module resolution remains stable
- Cross-repo imports are intentionally unsupported by runtime safety checks
- Use `has_key()` not `type()` for dictionary key checks
- `parse_json()` and `to_json()` are available builtins
