# Spec v1.0.1 hardening evaluation reproduction guide

This package compares the fixed release boundary `v1.0.0..v1.0.1`. It does not silently substitute the latest branch head.

## Contents

- `eval.json` — identical Kujo Eval requirements for both releases
- `scripts/eval_case.py` — deterministic fixtures and behavior assertions
- `scripts/run_eval.sh` — Eval runner and manifest verification
- `scripts/benchmark.py` — paired runtime/scaling benchmark
- `scripts/collect_static_metrics.py` — Git, archive, dependency, and lexical metrics
- `scripts/build_results.py` — machine-readable result assembly and paired bootstrap intervals
- `results/raw-benchmark.json` — every timed sample plus summaries
- `results/eval-*-final/` — Kujo Eval reports and checksum manifests
- `results/native-tests-*/` — native suite output
- `evaluation-results.json` — consolidated structured result
- `TECHNICAL_EVALUATION.md` and `PUBLIC_CASE_STUDY.md` — engineering and publication reports

## Prerequisites

- macOS or another Unix host with Bash, Git, Python 3, Perl, `shasum`, and `/usr/bin/time`
- Python package `psutil`
- Kujo runtime v1.1.0 for executing Spec (`SPEC_RUNTIME` below)
- Kujo Eval source v2.0.0 at commit `108b87f83fbaf52372b32c9e90e023953d0b77b6` (`EVAL_REPO`)
- a release-built Kujo runtime capable of running that Eval checkout (`EVAL_RUNTIME`)

The recorded run used macOS 26.3.1 on an Intel i7-9750H with 16 GiB RAM, Python 3.10.5, psutil 7.0.0, and Git 2.42.0. Use the same machine and runtime for both targets; do not compare mixed debug/release runtimes.

## Prepare fixed checkouts

From the Spec repository:

```bash
REPORT_ROOT="$PWD/evaluation/hardening-v1.0.1"
BASELINE_DIR="$(mktemp -d)/spec-v1.0.0"
CURRENT_DIR="$(mktemp -d)/spec-v1.0.1"
git worktree add --detach "$BASELINE_DIR" 11180d8f6af1ed3eea84abb3434dd736fa51293b
git worktree add --detach "$CURRENT_DIR" be4696b4acbefac39ea3c3645f27eb2bb6410f8e
```

Set these to authoritative local binaries/checkouts:

```bash
SPEC_RUNTIME=/absolute/path/to/kujo-v1.1.0
EVAL_RUNTIME=/absolute/path/to/eval-compatible/kujo
EVAL_REPO=/absolute/path/to/eval-at-108b87f83fbaf52372b32c9e90e023953d0b77b6
```

## Run the paired benchmark

```bash
python3 "$REPORT_ROOT/scripts/benchmark.py" \
  --baseline "$BASELINE_DIR" \
  --current "$CURRENT_DIR" \
  --kujo-bin "$SPEC_RUNTIME" \
  --output "$REPORT_ROOT/results/raw-benchmark.json"
```

Defaults are three warmups and ten measured pairs per workload, with twenty measured pairs for startup. Baseline/current order alternates in each pair. Expect the baseline scaling runs to take roughly 15 minutes on hardware similar to the recorded host.

## Run Kujo Eval against both targets

```bash
bash "$REPORT_ROOT/scripts/run_eval.sh" \
  "$EVAL_REPO" "$EVAL_RUNTIME" "$SPEC_RUNTIME" "$BASELINE_DIR" \
  "$REPORT_ROOT/results/eval-baseline-final"

bash "$REPORT_ROOT/scripts/run_eval.sh" \
  "$EVAL_REPO" "$EVAL_RUNTIME" "$SPEC_RUNTIME" "$CURRENT_DIR" \
  "$REPORT_ROOT/results/eval-current-final"
```

The baseline Eval command is expected to exit nonzero because shared requirements fail. `run_eval.sh` therefore stops before manifest verification on that target. After the expected run failure, verify its completed artifact set explicitly:

```bash
(cd "$EVAL_REPO" && "$EVAL_RUNTIME" run main.kujo verify-manifest \
  --output-dir "$REPORT_ROOT/results/eval-baseline-final" --json)
```

The recorded baseline 100-file Eval requirement hit the Eval command budget. The independent paired benchmark completed every baseline 100-file run and is the authoritative latency evidence.

## Run each release's native suite

```bash
(cd "$BASELINE_DIR"; set +e; env KUJO_BIN="$SPEC_RUNTIME" bash tests/run_tests.sh; code=$?; printf '%s\n' "$code" > "$REPORT_ROOT/results/native-tests-baseline/exit-code.txt"; exit "$code") \
  > "$REPORT_ROOT/results/native-tests-baseline/output.txt" 2>&1

(cd "$CURRENT_DIR"; set +e; env KUJO_BIN="$SPEC_RUNTIME" bash tests/run_tests.sh; code=$?; printf '%s\n' "$code" > "$REPORT_ROOT/results/native-tests-current/exit-code.txt"; exit "$code") \
  > "$REPORT_ROOT/results/native-tests-current/output.txt" 2>&1
```

Do not place the baseline checkout under a path containing `/tmp`; v1.0.0 has a native assertion that treats `/tmp` in reported source paths as a failure. The paired benchmark is unaffected by that assertion.

## Rebuild static and consolidated results

```bash
python3 "$REPORT_ROOT/scripts/collect_static_metrics.py" \
  --repo "$PWD" \
  --baseline 11180d8f6af1ed3eea84abb3434dd736fa51293b \
  --current be4696b4acbefac39ea3c3645f27eb2bb6410f8e \
  --output "$REPORT_ROOT/results/static-metrics.json"

python3 "$REPORT_ROOT/scripts/build_results.py" \
  --root "$REPORT_ROOT" \
  --output "$REPORT_ROOT/evaluation-results.json"
```

`build_results.py` uses a deterministic seed and 10,000 paired bootstrap resamples. Regenerated timestamps will differ; benchmark measurements should only be compared when the environment is controlled.

## Clean up fixed checkouts

After confirming no work is present in them:

```bash
git worktree remove "$BASELINE_DIR"
git worktree remove "$CURRENT_DIR"
```

## Audit trail

The Eval artifact manifests cover seven output files per target and were verified after the recorded run. `evaluation-results.json` links the boundary, environment, raw summaries, Eval outcomes, native tests, structural metrics, explicit regressions, and final conclusion. The raw benchmark retains all samples rather than only favorable aggregates.
