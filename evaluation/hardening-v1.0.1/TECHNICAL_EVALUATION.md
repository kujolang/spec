# Kujo Spec v1.0.1 Hardening Evaluation

## Executive summary

This evaluation compares the last official release before the hardening work, Spec `v1.0.0` at `11180d8f6af1ed3eea84abb3434dd736fa51293b`, with the hardened release `v1.0.1` at `be4696b4acbefac39ea3c3645f27eb2bb6410f8e`. The baseline was selected before measurements: it is the immediately preceding release, and the next commit begins the behavior-contract work that led into hardening. There are 11 commits in the comparison, spanning August 9–30, 2026.

The empirical result is positive but not uniformly faster. The dominant improvement is `validate-all`. Its old path checked the project boundary separately for every discovered file, launching two Python processes per check in addition to other shell helpers. The new path verifies the selected directory once and then validates the discovered regular files in one Python batch. On 100 identical valid JSON specs, median wall time fell from 40.1212 s to 0.9305 s (97.7%); p95 fell from 44.4235 s to 1.1769 s (97.4%); median sampled process count fell from 400 to 8. The output was byte-for-byte equivalent. The improvement grows with input size: 10 files improved 81.2%, 50 improved 95.6%, and 100 improved 97.7%. This is a scaling change, not a small constant-factor win.

Correctness, boundary safety, and failure behavior improved more broadly. An identical 11-requirement Kujo Eval suite passed 3/11 requirements on v1.0.0 and 11/11 on v1.0.1. The current version validates all documented schema fields, avoids a 256-failure exit-code wraparound, fails closed when the runtime fails, safely serializes interactive input, escapes graph labels, honors requested template formats, refuses a symlinked cache directory, and rejects invalid timeout configuration before executing work. Both releases passed the batch-completion and agent-context requirements, but batch latency differed sharply. Both emitted the same 996-byte context for the benchmark fixture, so no token or context reduction is demonstrated.

There are measurable costs. Single-file validation median rose from 2.5310 s to 3.1189 s (23.2%; paired bootstrap 95% interval 9.6%–30.4%), and median maximum RSS rose from 11.06 MiB to 13.25 MiB (19.8%). Strict invalid-schema validation rose 6.7% and returned 192 useful diagnostic bytes instead of incorrectly accepting the file with a 46-byte success response. The compressed source archive grew from 72,339 to 84,305 bytes (16.5%); source LOC grew 12.5%. Startup's 7.9% median increase is inconclusive because its paired interval crosses zero and p95 improved.

For actual users, v1.0.1 is substantially better when validating repositories, handling malformed input, or relying on automation exit status. Single-file validation is slower, and the implementation is larger. Those costs are operationally smaller than the batch scaling gain and the corrected failure semantics, but they are real and should remain visible in future comparisons.

Evidence classifications in this report are explicit:

- **Measured**: produced by the shared benchmark, Kujo Eval, native test runs, or deterministic Git analysis.
- **Observed**: directly present in source, output, or commit history.
- **Derived**: calculated from measured values.
- **Inferred**: a causal interpretation supported by source and measurements but not isolated by commit-by-commit benchmarking.
- **Not demonstrated**: unavailable or outside the executable behavior of this repository.

## Evaluation boundary

| State | Revision | Timestamp | Tag | Worktree at boundary |
|---|---|---|---|---|
| Baseline | `11180d8f6af1ed3eea84abb3434dd736fa51293b` | 2026-08-08 02:59:03 -04:00 | `v1.0.0` | detached clean checkout |
| Current | `be4696b4acbefac39ea3c3645f27eb2bb6410f8e` | 2026-08-30 19:07:40 -04:00 | `v1.0.1` | `main`, clean before evaluation artifacts were added |

`v1.0.0` is the only defensible immediate pre-hardening release. The first later commit, `a0a716e`, strengthens behavior contracts; subsequent commits implement output, validation, boundary, CI, and release changes. No alternate baseline was tested or selected for a more favorable result.

## Before/after scorecard

All latency rows are 10 measured runs after 3 warmups, except startup (20 measured runs). Percentages are reductions unless marked as increases.

| Metric | v1.0.0 | v1.0.1 | Change | Finding |
|---|---:|---:|---:|---|
| Kujo Eval shared requirements | 3/11 | 11/11 | +8 requirements | Clear improvement |
| Native release tests | 87/87 | 108/108 | +21 passing tests | Measured; suite sizes differ |
| 100-file batch median | 40.1212 s | 0.9305 s | 97.7% lower | Clear improvement |
| 100-file batch p95 | 44.4235 s | 1.1769 s | 97.4% lower | Clear improvement |
| 100-file throughput | 2.49 files/s | 107.47 files/s | 43.1× | Derived clear improvement |
| 100-file sampled process count, median | 400 | 8 | 98.0% lower | Clear improvement |
| 100-file maximum RSS, median | 9.87 MiB | 10.18 MiB | 3.2% higher | Small regression |
| Single validation median | 2.5310 s | 3.1189 s | 23.2% higher | Clear regression |
| Single validation p95 | 3.3123 s | 3.7127 s | 12.1% higher | Likely regression |
| Single validation maximum RSS, median | 11.06 MiB | 13.25 MiB | 19.8% higher | Regression |
| Agent export median | 1.6060 s | 1.5577 s | 3.0% lower | Inconclusive |
| Agent export bytes | 996 | 996 | unchanged | Neutral |
| Runtime failure median | 1.3389 s | 1.3052 s | 2.5% lower | Inconclusive |
| Runtime failure result | exit 0, one blank byte | exit 1, 53-byte diagnostic | truthful failure | Clear improvement |
| Direct dependencies | 0 | 0 | unchanged | Neutral |
| Compressed Git archive | 72,339 B | 84,305 B | 16.5% higher | Regression |
| Source LOC | 3,526 | 3,965 | 12.5% higher | Tradeoff |
| Test LOC | 940 | 1,117 | 18.8% higher | Increased coverage |

## What changed and why it matters

### Batch validation architecture

**Observed change.** `scripts/spec` moved `is_safe_path` from the per-file loop in `cmd_validate_all` to one check on the requested directory. Discovered inputs are constrained to regular files by `find -type f`, and the existing `validate-many` helper still receives the full list in one call. Return status changed from `return $failed` to a Boolean success expression.

**Previous problem.** The old boundary check started Python once for `abspath` and once for `realpath` for every file. The shell command also accumulated exit values directly; 256 failures became exit code 0 through POSIX modulo-256 behavior.

**Expected metrics.** Batch latency, CPU, subprocess count, scaling, and correct failure exit status.

**Measured result.** Median latency was 0.7734→0.7992 s at 1 file (3.3% slower and inconclusive), 4.1145→0.7751 s at 10 (81.2% lower), 20.8593→0.9130 s at 50 (95.6% lower), and 40.1212→0.9305 s at 100 (97.7% lower). Sampled process count was 8→8, 44→8, 202.5→8, and 400→8. At 100 files, median user+system CPU fell from 36.35 s to 0.78 s. The 256-invalid-file Eval case now exits nonzero instead of wrapping to success.

**Causal confidence.** High, but inferred rather than isolated: the process-count curve matches the removed per-file process launches, and output hashes are identical. No commit-level ablation was run.

### Schema and type validation

**Observed change.** `scripts/spec_helpers.py` and `src/validate.kujo` now recognize the full schema and validate status, UUID v4, numeric hours, metadata, structured dependencies, nested eval requirements, risks, collection limits, string lengths, and nonempty acceptance criteria. Repeated membership loops in the Kujo implementation were consolidated into `contains`.

**Previous problem.** Valid documented fields were treated as unknown, while malformed nested and typed values could pass. The current full-schema fixture fails under v1.0.0 with four “unknown field” warnings and passes under v1.0.1.

**Expected metrics.** Correctness, deterministic validation, diagnostic output, and possibly single-file latency/RSS.

**Measured result.** The shared full-schema Eval requirement changed from fail to pass. A deliberately invalid schema changed from an incorrect exit 0/46-byte success to exit 1/192-byte diagnostic. That stricter path is 6.7% slower at the median and uses 21.0% more median maximum RSS. Typical valid single-file validation is 23.2% slower with 19.8% higher RSS.

**Conclusion.** Clear correctness improvement with a measurable small-workload runtime cost.

### Fail-closed output and format boundaries

**Observed change.** Render and export no longer suppress runtime errors and continue with empty output. They now require successful, nonempty runtime output. Export formats and conversion targets are allowlisted. Template initialization converts to the requested format instead of copying a differently formatted source.

**Measured result.** Runtime failure changed from success with a blank byte to failure with a 53-byte diagnostic. Requested JSON initialization changed from invalid JSON to valid JSON. Render success output remained byte-for-byte identical and its median was statistically neutral (-0.4%; paired interval -5.4% to +10.7%).

### Input, graph, cache, and timeout boundaries

**Observed change.** Interactive initialization validates the name, requires a goal, and serializes structured data with safe YAML or JSON output. Mermaid and DOT labels are JSON-escaped. Cache storage moved from a shared `.spec_cache` name to a per-user mode-0700 directory and refuses a symlinked cache root. `SPEC_TIMEOUT` must be a positive integer before command dispatch.

**Measured result.** All four corresponding shared Eval requirements fail on v1.0.0 and pass on v1.0.1. These are behavior outcomes, not simulated scores.

### CI and release reproducibility

**Observed change.** CI installs the declared runtime through a checksum-pinned script; portability checks account for runner differences; release automation validates versions and builds artifacts more deterministically. The release metadata was aligned at v1.0.1.

**Measured result.** The v1.0.1 native suite passes 108/108, including the added supply-chain and portability contracts. v1.0.0 passes its own 87/87 tests when run from a path that does not trigger its `/tmp` source-path assertion. Clean build and release build time are not applicable: Spec is a shell/Python/Kujo source package with no compiled project artifact. Release archive size was approximated reproducibly using `git archive`.

## Runtime performance and scaling

| Workload | n | Baseline median | Current median | Median change | Baseline p95 | Current p95 | Paired median-change 95% interval |
|---|---:|---:|---:|---:|---:|---:|---:|
| Startup/version | 20 | 0.1268 s | 0.1368 s | +7.9% | 0.1871 s | 0.1647 s | -1.3% to +15.8% |
| Validate one valid spec | 10 | 2.5310 s | 3.1189 s | +23.2% | 3.3123 s | 3.7127 s | +9.6% to +30.4% |
| Agent export | 10 | 1.6060 s | 1.5577 s | -3.0% | 2.0106 s | 1.7157 s | -12.5% to +2.0% |
| Render | 10 | 1.5083 s | 1.5029 s | -0.4% | 1.5799 s | 1.7041 s | -5.4% to +10.7% |
| Invalid schema | 10 | 2.3601 s | 2.5184 s | +6.7% | 2.5799 s | 2.6725 s | +3.5% to +11.4% |
| Runtime failure | 10 | 1.3389 s | 1.3052 s | -2.5% | 1.5703 s | 1.4944 s | -8.6% to +0.8% |
| Validate-all 1 | 10 | 0.7734 s | 0.7992 s | +3.3% | 0.8594 s | 0.8615 s | -2.1% to +8.2% |
| Validate-all 10 | 10 | 4.1145 s | 0.7751 s | -81.2% | 4.6103 s | 0.8673 s | -82.5% to -80.1% |
| Validate-all 50 | 10 | 20.8593 s | 0.9130 s | -95.6% | 22.2137 s | 1.0636 s | -96.0% to -95.1% |
| Validate-all 100 | 10 | 40.1212 s | 0.9305 s | -97.7% | 44.4235 s | 1.1769 s | -97.9% to -97.5% |

Minimum, maximum, mean, median, standard deviation, p95, p99, CPU, RSS, I/O counters, output hashes, and all samples are retained in `results/raw-benchmark.json`. P99 is recorded but not emphasized because 10 samples do not support a stable tail estimate.

The baseline batch curve is approximately linear after fixed startup: an additional file costs roughly 0.40 s. The current curve is nearly flat across 10–100 JSON files because the batch is handled in one helper process; 100 files add only about 0.16 s over 10. This does not prove constant complexity for arbitrarily large files: parsing and validation work must eventually scale with total input bytes. It demonstrates removal of the dominant per-file process overhead within the tested range.

Disk block reads and writes were zero in the measured successful paths after warmup, as reported by macOS `time`. Allocation counts were not measured. RSS is command-level maximum resident set size, not an allocation profile. Sampled process counts are lower bounds for short-lived children.

## Token, context, and agent efficiency

Spec does not call an LLM in the tested paths. Model, provider, prompt tokens, completion tokens, cached tokens, reasoning cycles, and dollar cost therefore do not exist for this comparison. Claiming token savings would be unsupported.

The agent-facing `export-agent-context` workload was measured at the process boundary:

| Metric | Baseline | Current | Change |
|---|---:|---:|---:|
| Successful completion | yes | yes | unchanged |
| stdout | 996 bytes | 996 bytes | unchanged |
| content hash | `7d84edd4…` | `7d84edd4…` | identical |
| median latency | 1.6060 s | 1.5577 s | 3.0% lower, inconclusive |
| median sampled process count | 10.5 | 12 | higher, sampling-sensitive |

The separate Eval fixture emitted 434 bytes on both releases and retained the task name and acceptance criteria. Agent quality and context size are therefore neutral for successful exports. Failure usability improved: agents now receive an explicit diagnostic and nonzero status rather than a blank successful result. No live-agent task, tool-call trace, or tokenized model session was run; agentic cycle and cost claims are **not demonstrated**.

## Kujo Eval report

The repository now contains an 11-test deterministic Eval suite and case runner. The same `eval.json`, commands, fixtures, runtime, and policy were used against both checkouts. Kujo Eval's actual output is pass/fail per requirement; the table reports those counts rather than an invented weighted score.

| Primary category | Baseline | Current | Delta |
|---|---:|---:|---:|
| Correctness (version, full schema, requested format) | 1/3 | 3/3 | +2 |
| Batch completion (100 files within 120 s) | 1/1 | 1/1 | 0 |
| Reliability/failure (256 exit, runtime failure, timeout) | 0/3 | 3/3 | +3 |
| Agent usability (bounded useful context) | 1/1 | 1/1 | 0 |
| Boundary/output safety (interactive, graph, cache) | 0/3 | 3/3 | +3 |
| **Overall framework result** | **3/11** | **11/11** | **+8** |

The Eval requirement gives both releases a generous 120-second budget and therefore treats both as functionally complete. The independent paired benchmark supplies the performance discrimination: 40.1212 s baseline versus 0.9305 s current at the median. Total suite duration (100,503 ms baseline versus 10,906 ms current) is not used as a speedup metric because the baseline's 256-failure stress case dominates it and Eval includes harness overhead.

Both artifact manifests were independently verified after execution: seven SHA-256 entries each. Raw `last_run.json`, reports, histories, summaries, badges, and manifests are preserved under `results/eval-*-final/`.

Eval's generated baseline Markdown renders “Pass Rate 0%” even though the same report and `last_run.json` record 3 passed and 8 failed. This evaluation treats the integer outcomes as authoritative and derives 27.3% only when a rate is needed. The display defect is not attributed to Spec.

## Build, artifact, dependency, and complexity analysis

| Structural metric | Baseline | Current | Change |
|---|---:|---:|---:|
| Tracked files | 71 | 74 | +4.2% |
| Source LOC | 3,526 | 3,965 | +12.5% |
| Test LOC | 940 | 1,117 | +18.8% |
| Documentation LOC | 1,770 | 1,922 | +8.6% |
| Approximate function definitions | 59 | 62 | +5.1% |
| Approximate branch tokens | 793 | 928 | +17.0% |
| TODO/FIXME count | 0 | 0 | unchanged |
| Direct npm dependencies | 0 | 0 | unchanged |
| Compressed Git archive | 72,339 B | 84,305 B | +16.5% |

These are deterministic lexical metrics, not claims of semantic complexity. Complexity was both consolidated and added: repeated Kujo membership loops were genuinely consolidated, while validation rules, boundary handling, release installation, and tests added code and branches. The result is more behavior and more explicit policy, not a smaller codebase. No compiled binary, transitive package graph, unsafe Rust, compiler warning, Cargo build, or incremental build exists in this repository, so those metrics are not applicable.

## Reliability and determinism

The baseline's own release suite passes 87/87; current passes 108/108. This is evidence that each release satisfies its contemporary contracts, but the counts are not a fair before/after quality score because the suite changed. The shared Eval suite supplies that comparison.

Repeated benchmark outputs were deterministic for successful workloads: output hashes were stable within each target, and successful output hashes match between targets for validate, batch validate, render, and agent export. Expected differences occurred for version and corrected failure outputs. Ten repeated runtime-failure and schema-failure runs produced stable exit codes and outputs. No flakes were observed within the measured repetitions.

## Root-cause and commit attribution

| Commit | Change | Intended effect | Observed/measured effect |
|---|---|---|---|
| `a0a716e` | Stronger behavior tests | Expose contract gaps | More deterministic coverage; no isolated runtime measurement |
| `70c5a41` | Honor requested output formats | Correct generated artifact type | Shared format requirement fails before and passes after |
| `7d5cdd9` | Align validators with schema | Accept valid fields; reject malformed structure | Full-schema requirement fails before and passes after; stricter invalid diagnostic |
| `d510334` | Consolidate validator lookup loops | Reduce duplication | Membership logic simplified; net source/branch count still rises across release |
| `3515975` | Batch path check, Boolean exits, fail-closed output, safe input/graph/cache/timeout | Performance, correctness, boundary safety | 100-file median -97.7%; process count 400→8; seven failure/boundary outcomes corrected |
| `dbc41a9` | Record hardening architecture/audit | Maintainability | Documentation LOC increased; no runtime effect claimed |
| `82f9128` | Ignore root test scratch files | Cleaner developer state | Git hygiene observed; no runtime effect claimed |
| `1630e05` | Checksum-pinned runtime installer | Reproducible CI supply chain | Added native contract coverage; build-time effect not measured |
| `13c1775` | Runner-portable checks | CI reliability | Current native suite passes locally; cross-runner reliability not independently measured |
| `35b61da` | Reproducible release automation | Safer releases | Source inspection and tests only; release-time performance not measured |
| `be4696b` | Align v1.0.1 release metadata | Coherent release | Version contract returns v1.0.1; no speed effect |

The most important causal chain is:

`3515975` removes per-file path-resolution subprocesses → batch process count becomes fixed within the measured range → CPU and wall time no longer grow by roughly 0.4 s per file → 100-file median falls 40.1212→0.9305 s while output remains identical.

The main tradeoff chain is:

`7d5cdd9` and `3515975` add full typed/nested validation and safer cache setup → valid and invalid single-file paths perform more checks and use a different cache boundary → single-file median rises 2.5310→3.1189 s and RSS rises 11.06→13.25 MiB → malformed specs are rejected with actionable diagnostics instead of accepted.

## Top improvements

1. **Batch scaling and tool efficiency.** At 100 files, median time fell 97.7%, median CPU fell about 97.9%, and sampled processes fell 98.0%, with identical output. This materially changes repository-scale developer and agent workflows.
2. **Truthful failure semantics.** Runtime failures and 256-file failure batches now return nonzero. Automation can trust exit status instead of continuing from empty or wrapped-success results.
3. **Schema correctness.** Documented full-schema specs validate, while malformed types and nested values are rejected. This reduces silent contract drift.
4. **Boundary safety.** Interactive serialization, graph escaping, private cache handling, and timeout validation all pass explicit adversarial requirements that baseline fails.
5. **Release reproducibility.** Runtime installation is versioned and checksum-pinned, and release automation has stronger consistency checks. This is observed and tested structurally, though CI variance was not benchmarked.

## Regressions and Tradeoffs

| Metric | Baseline | Current | Severity | Likely cause | Assessment / action |
|---|---:|---:|---|---|---|
| Single valid validation median | 2.5310 s | 3.1189 s | Low–medium | Added schema checks and cache hardening | Real regression; profile before the next optimization pass |
| Single valid maximum RSS | 11.06 MiB | 13.25 MiB | Low | More validation/runtime state | Acceptable for a CLI, but track |
| Invalid schema median | 2.3601 s | 2.5184 s | Low | Correct nested/type validation | Acceptable correctness tradeoff |
| Invalid schema output | 46 B success | 192 B diagnostic | Beneficial volume increase | Actionable error evidence | Do not “optimize” away |
| 100-file maximum RSS | 9.87 MiB | 10.18 MiB | Low | Batched helper/current runtime state | Acceptable against 97.7% latency gain |
| Compressed archive | 72,339 B | 84,305 B | Low | CI installer, validation, tests, docs | Acceptable; source package remains small |
| Source LOC / branch tokens | 3,526 / 793 | 3,965 / 928 | Maintainability tradeoff | More explicit policy and validation | Watch for rule drift between Python and Kujo validators |

Startup is not listed as a regression: median was 7.9% slower, but its 95% paired interval crosses zero and p95 improved 12.0%. Agent export and render differences are also inconclusive.

## Remaining opportunities

- **P1 — Profile single-file validation.** The 23.2% median and 19.8% RSS regressions are clear. Use process-level profiling to separate runtime startup, cache initialization, conversion, and duplicate Python/Kujo validation work before changing behavior.
- **P1 — Prevent validator drift.** Python and Kujo implementations encode parallel validation rules. Generate shared fixtures or rule data so future schema additions cannot diverge.
- **P2 — Add a permanent batch performance gate.** Preserve a generous, hardware-normalized threshold or process-count ceiling so per-file subprocess behavior cannot return.
- **P2 — Correct Eval evidence presentation and policy diagnostics.** Eval renders a 0% baseline pass rate despite recording 3/11 passes. During suite construction, safe repository paths containing `eval` and a path segment normalized to `nc ` were also rejected by substring policy. The final suite avoids those strings and uses integer outcomes, but both behaviors belong to Kujo Eval and are cross-repository follow-ups.
- **P3 — Add Linux comparison data.** This evaluation is macOS/x86_64 only. CI portability changes warrant a Linux runner sample before making cross-platform performance claims.

No remaining P0 correctness or performance issue was found within the tested workloads.

## Benchmark methodology

### Environment

- macOS 26.3.1, Darwin 25.3.0, x86_64
- Intel Core i7-9750H, 6 physical / 12 logical cores
- 16 GiB RAM
- Python 3.10.5; psutil 7.0.0; Git 2.42.0
- Kujo Spec execution runtime 1.1.0 for both targets
- Kujo Eval 2.0.0 source at commit `108b87f83fbaf52372b32c9e90e023953d0b77b6`, executed by its pinned release-built Kujo runtime
- Same local APFS volume, no network, no LLM provider

### Workload controls

Fixtures are generated from the same functions for both targets in target-local ignored directories. Baseline and current runs alternate order inside each pair. Each workload gets three warmups. There are 10 measured pairs, or 20 for startup. Commands, inputs, runtime, environment variables, timeout, and capture logic are otherwise identical. Successful comparison outputs are hashed to detect semantic drift.

Wall time uses `perf_counter_ns` around `/usr/bin/time -lp`. User time, system time, maximum RSS, page and block I/O counters come from `time`. psutil samples descendant PIDs every 1 ms; this is explicitly a lower bound. Median is the primary latency statistic. Min, max, mean, standard deviation, p95, and p99 are retained. A deterministic 10,000-resample paired bootstrap estimates the 95% interval for median percentage change; it quantifies these samples, not all machines.

### Limitations

- One macOS x86_64 host; no thermal, frequency, or background-load instrumentation.
- Ten samples support central and p95 comparisons, not robust p99 claims.
- RSS is not an allocation count or whole-process-tree memory integral.
- Generated specs are representative contract fixtures, not a corpus of every production spec shape.
- JSON batch scaling avoids YAML/TOML conversion cost; single validation and agent/render paths cover conversion/runtime startup separately.
- No live agent, LLM, network, or provider workload exists here; token, tool-cycle, and dollar-cost metrics are not demonstrated.
- Commit attribution combines diff evidence with end-state measurements; individual commits were not benchmarked in isolation.
- Kujo Eval 2.0.0's generated baseline pass-rate display is inconsistent with its recorded pass/fail counts; this report uses the counts.

## Evidence classification summary

| Claim | Classification |
|---|---|
| Batch median, p95, CPU, RSS, process counts, output hashes | Measured |
| Shared requirement and native test outcomes | Measured |
| LOC, archive size, dependencies, commit/file counts | Measured deterministically from Git |
| Batch speedup originates primarily from moving path safety out of the file loop | Inferred with high confidence from source and process scaling |
| Stricter validation causes all single-file regression | Inferred; not fully isolated |
| Token savings, dollar savings, live-agent cycle reduction | Not demonstrated |
| Cross-platform speedup | Not demonstrated |

## Final question

> If we erase the commit messages and ignore what the hardening work intended to accomplish, does the empirical evidence independently demonstrate that CURRENT is a better engineered version than BASELINE?

**YES.** The shared workload independently shows 11/11 requirements satisfied instead of 3/11, a 40.1212→0.9305 s 100-file median with identical successful output, fixed batch process overhead instead of linear process growth, correct nonzero failure statuses, and stable release-specific test suites. This conclusion survives the observed losses: single-file validation is 23.2% slower, its RSS is 19.8% higher, and the source archive is 16.5% larger. The evidence supports “better engineered,” not “faster everywhere” or “leaner in every dimension.”
