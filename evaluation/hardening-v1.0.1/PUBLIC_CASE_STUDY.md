# Hardening Kujo Spec

## Why we did it

Kujo Spec turns task contracts into deterministic validation, rendered documents, and agent context. Its v1.0.1 hardening pass targeted a practical set of risks: repository-scale validation overhead, schema drift, misleading success exits, unsafe serialization boundaries, and reproducible CI/release behavior.

We evaluated the result rather than treating the refactor as proof. The comparison uses the immediately preceding release, v1.0.0 (`11180d8`), and the hardened v1.0.1 release (`be4696b`). Both versions ran the same fixtures with the same Kujo runtime on the same machine.

## What changed

The largest architectural change is in batch validation. v1.0.0 re-resolved the project boundary for every discovered file, repeatedly launching helper processes. v1.0.1 verifies the selected directory once, discovers regular files beneath it, and validates the list in one helper batch.

The release also:

- validates the complete documented schema and nested value types;
- returns Boolean failure status instead of returning the raw failure count;
- fails closed when rendering or export cannot run;
- safely serializes interactive YAML and escapes graph labels;
- refuses symlinked shared cache roots;
- validates timeout and output-format inputs;
- installs a checksum-pinned runtime in CI and strengthens release consistency checks.

## How we measured it

The benchmark alternated baseline and current runs in pairs. Each workload received at least three warmups and ten measured runs; startup received twenty. We captured wall and CPU time, maximum RSS, sampled process count, output bytes, and output hashes. Scaling workloads used 1, 10, 50, and 100 identical valid JSON specs.

A separate 11-requirement Kujo Eval suite covered minimal, typical, large, stress, failure, agent-facing, and adversarial boundary behavior. Raw samples, Eval artifacts, manifests, methodology, and scripts are committed with the report.

## Before vs. after

| Metric | v1.0.0 | v1.0.1 | Change |
|---|---:|---:|---:|
| Shared Eval requirements | 3/11 | 11/11 | +8 |
| 10-file validation median | 4.1145 s | 0.7751 s | 81.2% lower |
| 50-file validation median | 20.8593 s | 0.9130 s | 95.6% lower |
| 100-file validation median | 40.1212 s | 0.9305 s | 97.7% lower |
| 100-file p95 | 44.4235 s | 1.1769 s | 97.4% lower |
| 100-file sampled processes, median | 400 | 8 | 98.0% lower |
| 100-file successful output | 48 bytes | 48 bytes | identical hash |
| Single validation median | 2.5310 s | 3.1189 s | 23.2% higher |
| Single validation maximum RSS | 11.06 MiB | 13.25 MiB | 19.8% higher |
| Agent context output | 996 bytes | 996 bytes | unchanged |
| Compressed source archive | 72,339 B | 84,305 B | 16.5% higher |

## Biggest improvements

Batch validation changed its scaling behavior. At one file, both versions take about 0.8 seconds. At 100 files, v1.0.0 reaches 40.1 seconds while v1.0.1 remains below one second at the median. That is consistent with removing per-file process startup from the dominant path.

Automation is also more trustworthy. A batch containing exactly 256 failures used to return exit code 0 because the raw count wrapped at the process boundary. A failed runtime could also yield a blank successful render. Both cases now fail nonzero, and runtime failure includes an actionable diagnostic.

## What surprised us

The largest result did not come from a new algorithm inside the validator. It came from moving a correct but expensive boundary operation to the correct scope: once per selected directory instead of once per file. At 100 files, median sampled process count fell from 400 to 8.

The hardening work also made some common operations slower. Full schema checking is not free. Typical single-file validation is 23.2% slower and uses 19.8% more maximum RSS in this environment.

## What did not improve

Agent context did not get smaller: the representative export remained byte-for-byte identical at 996 bytes. Its 3.0% median latency improvement was within noise. Startup and render changes were also inconclusive.

This repository does not invoke an LLM, so no token or dollar savings are claimed. The source package is larger, not leaner: the compressed Git archive grew 16.5% as validation, CI, tests, and documentation were added.

## What remains

The next evidence-backed target is single-file validation. It should be profiled to separate runtime startup, cache initialization, conversion, and duplicated validation work before making another change. The parallel Python and Kujo validation rules also need long-term drift protection through shared fixtures or generated rule data.

## Reproducing the results

See [README.md](README.md) for exact commands. The complete engineering analysis is in [TECHNICAL_EVALUATION.md](TECHNICAL_EVALUATION.md), machine-readable summaries are in [evaluation-results.json](evaluation-results.json), and raw evidence is under `results/`.
