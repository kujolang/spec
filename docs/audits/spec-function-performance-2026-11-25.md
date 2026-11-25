# Spec function performance audit

## Repository

- Scope was function-level latency in `kujolang/spec` on `main`, starting at `36da0d7216587809e32dedb91dee3cf4b9e50af1`. The verified implementation ends at `edb11b5ffc23d84f9c3defce8e3b829c5009d723`.
- Spec's Bash CLI coordinates filesystem access and Kujo runtime calls. Python handles metadata and batch validation. The schema and exports serve Eval, Dispatch and other Kujo consumers. The [August audit](repository-hardening.md) records the earlier work.

## Baseline

The starting tree passed 108 CLI tests. The standalone benchmark validated all 100 JSON specs in 0.98 seconds within the 30-second local budget. The paired measurements below use the starting implementation as the baseline for the commands affected by this pass.

## Findings and changes

| ID | Priority | Function or path | Evidence and change | Status |
| --- | --- | --- | --- | --- |
| SPEC-P01 | P1 | `spec_to_json` | JSON already matched the target format. Copy it after the size check, bypassing pathname hashing, content hashing and cache validation. YAML and TOML retain their conversion cache. | Fixed |
| SPEC-P02 | P1 | `is_safe_path` | A normal file read launched separate processes to resolve the working directory, lexical path and symlink target. Perform both boundary checks together with the same diagnostics. | Fixed |
| SPEC-P03 | P1 | `cmd_validate` | The wrapper repeatedly decoded the runtime receipt for warnings, exit status and presentation. Merge warnings and render the receipt in one helper. | Fixed |
| SPEC-P04 | P1 | `cmd_info` | Text output launched six interpreters and reread the same spec. Collect fields and counts in one parse. | Fixed |
| SPEC-P05 | P2 | `cmd_info`, `cmd_status` | JSON info and status mutations routed their input through a separate file-dump process. The final consumer now loads the staged JSON directly. | Fixed |
| SPEC-P06 | P1 | `cmd_search` | Name, priority and tags were each read in a separate interpreter. Extract all three in one parse and keep the existing filtering rules. | Fixed |
| SPEC-P07 | P1 | `spec_cmd_graph` | Each node used four Python invocations for metadata and escaping. One helper handles both graph formats for the whole graph. | Fixed |
| SPEC-P08 | P1 | Graph parent lookup | Each nonempty parent reference could trigger a full node scan. Build a first-occurrence index, so lookup work grows with nodes and edges. | Fixed |
| SPEC-P09 | P1 | `validate_file_quiet` | JSON CI ran separate path, size and validation commands per file. One interpreter performs all three checks. | Fixed |
| SPEC-P10 | P2 | `spec_cmd_ci` | Parallel CI wrote and read an extra path file per worker and forked to read results. Reuse the ordered input array and read results with a Bash builtin. | Fixed |
| SPEC-P11 | P2 | `dict_get_arr` | Render and export rebuilt native arrays element by element. Return the parsed array directly, preserving handling of other input types. | Fixed |

The CLI regression covers graph escaping and duplicate IDs, matching search, text and JSON metadata, and parallel CI failure ordering. Existing fixtures also exercise YAML and TOML conversion, strict validation, safe reads and writes, and agent and Dispatch exports.

## Runtime measurements

Both revisions ran on the same Intel macOS 26.6.2 host with Kujo 1.5.0, the available local runtime, and Python 3.10.5. The host was shared with other active builds. Each measurement alternated revisions, used one warm-up and three measured runs per revision, and compared exit success and stdout bytes across revisions. The directory benchmark used eight small JSON specs with priority, tags and a parent chain. Render used a JSON spec with 200 paths and 100 acceptance criteria. These are end-to-end elapsed times on that host.

| Workload | Baseline median (range), ms | Optimized median (range), ms |
| --- | ---: | ---: |
| `validate --strict --json` | 6,495 (5,317–7,265) | 2,662 (2,513–3,467) |
| `info` | 10,337 (7,454–14,409) | 1,584 (1,361–1,972) |
| `info --json` | 4,139 (2,977–4,459) | 1,718 (1,522–1,794) |
| `list --json` | 14,487 (12,561–16,216) | 1,338 (1,204–1,380) |
| `search` with tag and query filters | 13,645 (11,529–25,681) | 3,230 (2,022–4,425) |
| `graph` (Mermaid) | 14,177 (13,196–29,385) | 779 (727–1,106) |
| `ci --format json` | 5,176 (3,896–5,190) | 2,089 (1,937–2,297) |
| `ci --format json --jobs 4` | 1,159 (1,156–1,160) | 480 (473–530) |
| `render` | 842 (836–849) | 345 (342–348) |
| Kujo render module directly | 105 (103–107) | 97 (96–99) |

The search timing includes reading and filtering eight specs and preserves the baseline tag filter behavior described under Remaining work. A separate regression exercises matching results with the priority and query filters.

The graph lookup complexity and removed subprocesses are supported by the implementation. Status mutation was covered by behavior checks. Memory, build, artifact size and model-token effects were outside the measurement scope.

## Compatibility and scope

The command surface, successful output, schemas, configuration and environment variables retain their existing contracts. JSON CI applies its size limit to the file it validates. Structured exports and agent-context content remain compatible. The pass reviewed command output and error handling, agent-facing payloads, path and symlink checks, graph escaping, temporary files, and worker ordering. Metadata is collected within each command, with no newly shared state or dependency. The existing runtime timeout and YAML/TOML cache contract are retained.

The checklist covered repository context and baseline (0–1), complexity, runtime and resource use (2–4), agent context, receipts and error paths (5–7), filesystem boundaries, worker ordering and CLI contracts (8–10), dependencies, tests and CI gates (11–13), and architecture docs, agent use and dead weight (14–16). Model/provider integrations, network orchestration, tool registration, release artifact optimization, and broad dependency or security changes were outside the requested runtime scope. No cross-repository changes are required.

## Remaining work

- P2. `spec search --tag` checks a space-delimited substring in serialized JSON. Both revisions returned zero for `--tag speed` on eight specs with `"tags": ["speed"]`. Track exact tag matching separately from the speed pass. SignalBox Capture `cap_091e877a-2535-41b3-a529-fcef327ed186`.

## Verification receipt

| Command | Baseline | Optimized |
| --- | --- | --- |
| `bash tests/run_tests.sh` | 108 passed | 109 passed |
| `bash tests/benchmark.sh` | 100 validated in 0.98 s | 100 validated in 0.76 s |
| `bash scripts/verify_docs_command_parity.sh` | 31 passed | 31 passed |
| `bash scripts/verify_completion_parity.sh` | 132 passed | 132 passed |
| `bash scripts/verify_test_runtime_parity.sh` | 3 passed | 3 passed |
| `bash scripts/release_quality_gates.sh` | 20 passed | 20 passed |
| `bash scripts/supply_chain_policy_check.sh` | 13 passed | 13 passed |
| `git diff --check 36da0d7 HEAD` | Starting tree clean | Passed |

The full suite reran on an isolated checkout of the final implementation after correcting an in-flight regression fixture that used the known tag filter. The standalone benchmark also reran in isolation after overlapping runs contended for its fixed fixture directory. The table uses the isolated receipts. Existing timing budgets remain in `tests/benchmark_trend_budgets.json`; this pass adds behavior checks and uses the existing budgets without adding host-sensitive timing thresholds.
