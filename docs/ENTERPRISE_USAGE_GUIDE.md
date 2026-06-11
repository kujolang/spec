# Enterprise Usage Guide

This guide describes how to run Spec in large monorepos and regulated environments with auditable controls.

## 1. Monorepo Layout

Recommended structure:

```text
monorepo/
├── services/
│   ├── api/
│   │   ├── specs/
│   │   └── src/
│   └── web/
│       ├── specs/
│       └── src/
├── platform/
│   ├── specs/
│   └── infrastructure/
└── .github/workflows/
```

Use colocated specs per bounded context and validate in each package path.

## 2. Regulated Environment Controls

### Deterministic CI validation

Use bounded scans with explicit runtime controls:

```bash
spec ci ./services/api/specs --format json --max-files 500 --jobs 4 --strict
```

### Safe write boundaries

Enable safe-write mode in CI runners:

```bash
export SPEC_SAFE_WRITE=on
```

Only use `--unsafe-write` in approved build steps.

### Template source policy

For locked-down environments, block home-directory templates:

```bash
export SPEC_TEMPLATE_SOURCE_POLICY=project-only
```

Per-command override for strict project-template lookup:

```bash
spec init --from template:feature --strict-template-source --output specs/new-feature.spec.yml
```

## 3. CI Pipeline Pattern

Example GitHub Actions workflow:

```yaml
name: spec-governance
on: [pull_request]

jobs:
  spec-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Kujo runtime
        run: echo "Set KUJO_BIN in your CI environment"
      - name: Validate specs
        run: |
          export SPEC_SAFE_WRITE=on
          export SPEC_TEMPLATE_SOURCE_POLICY=project-only
          bash scripts/verify_docs_command_parity.sh
          bash scripts/verify_completion_parity.sh
          bash tests/run_tests.sh
          bash scripts/release_quality_gates.sh
```

## 4. End-to-End Example

### Step 1: Author spec

```bash
spec init --name "Harden auth session revocation" --output services/api/specs/auth-session-revoke.spec.yml
```

### Step 2: Validate in strict mode

```bash
spec validate services/api/specs/auth-session-revoke.spec.yml --strict
```

### Step 3: Export machine-readable envelope for downstream automation

```bash
spec export services/api/specs/auth-session-revoke.spec.yml \
  --format envelope \
  --payload-format dispatch \
  --output artifacts/auth-session-revoke.envelope.json
```

### Step 4: Enforce CI budgets and trend guard

```bash
SPEC_BENCH_PROFILE=ci-linux bash tests/benchmark.sh
```

### Step 5: Release readiness

```bash
bash scripts/release_quality_gates.sh
bash scripts/supply_chain_policy_check.sh
```

## 5. Audit-Friendly Artifacts

Collect and retain:

- `tests/artifacts/benchmark_summary.json`
- `dist/*.provenance.json`
- `docs/COMMAND_INVENTORY.md`
- Release notes created from `docs/RELEASE_NOTES_TEMPLATE.md`

This package provides traceability for change intent, validation results, and release evidence.
