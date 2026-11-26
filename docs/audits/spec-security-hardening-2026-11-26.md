# Spec security hardening

## Repository and baseline

- Repository and branch — `kujolang/spec`, `main`.
- Starting checkout — `b1c7a6a34a08f6d07d000616b613d8e9322a3476`, clean.
- Integration baseline — `8f70eb2f16dfe3863e20d2e2ba22d870f4350776`.
- Ending implementation — `01694d3a47019ffd05338b7ae2dbece814fdf7eb`.
- Spec validates, discovers, renders, and exports task contracts. Bash routes the CLI, Python handles filesystem and JSON operations, and Kujo parses and renders. Eval, Dispatch, agent-context exports, GitHub CLI issue imports, and package entry points are integration boundaries.

The first run in the default macOS temporary directory hit `No space left on device`. With scratch space on a separate local volume, the starting checkout passed 110 CLI checks, 31 documentation checks, 132 completion checks, three runtime-parity checks, and the 100-file benchmark in 3.48 seconds with Kujo 1.5.0.

Fetching `origin/main` during the audit revealed two commits ahead of the initial tracking ref, `e154a01` and `8f70eb2`. Those commits already added bounded conversion snapshots, private atomic cache records, dangling-symlink checks, CI filename escaping, least-privilege CI credentials, and runnable installer packaging. The final changes build on those commits. The acceptance baseline and final comparison below use the same checksum-verified Kujo 1.1.0 macOS runtime as the repository's CI. An integration run hit the space error again because macOS `mktemp -t` chose the system temp directory. Explicit templates and the test harness now place scratch files under the selected temp directory. The native Bash 3.2 still uses the system volume for here-documents. Native checks were retried, and the aggregate release gate used a checksum-verified Bash 5.3 build in the disposable test environment.

## Findings and fixes

| Priority | Boundary | Finding and static evidence | Resolution |
| --- | --- | --- | --- |
| P0 | GitHub issue import | `_init_from` inserted the destination path directly into executable Python text. GitHub CLI input was also passed before the end of option parsing. | Pass the filename as an argument to a fixed serializer. Pass the issue after `--`. Support the documented `owner/repo/number` form with `--repo`. Open new import destinations exclusively. |
| P0 | Temporary files | CLI cleanup traps expanded the temporary path into shell source. Shell metacharacters and whitespace in a caller's temp directory could change cleanup behavior. | Use command-local exit traps that quote the path at execution and explicitly place scratch files under the caller's `TMPDIR`. |
| P0 | Safe-write | The `-` exemption skipped containment checks, even though commands could treat it as a literal filename. | Check the literal path like any project destination. Retain the explicit standard-stream paths and the documented override. |
| P0 | Lifecycle updates | `status --set` used a predictable backup name, wrote to the live target, and validated after the write. Failure and interruption could leave invalid content or change symlink behavior. | Stage beside the resolved file, validate the candidate and verify its status, compare the live file against the bounded original snapshot, preserve ordinary permission bits, and publish by atomic replacement. |
| P0 | Spec discovery and validation | `list` and `graph` could read outside the project. Their discovery and the non-CI batch commands split filenames on newlines. `validate-all` applied the converted JSON ceiling to raw JSON and passed a potentially long filename list through process arguments. | Reuse upstream CI's project-scoped NUL-delimited walker. Use the 1 MiB source limit for raw JSON and the existing converted-document limit for trusted intermediates. Pass batch paths through standard input. |
| P0 | Export evidence | An envelope exported from a bounded source read and then reopened the source to calculate its checksum. A concurrent edit could make the checksum describe different bytes. | Hash the same bytes used for conversion, including on a cache hit. Stream the rendered payload to the envelope serializer over stdin. |
| P0 | Subprocess arguments | `changelog` passed a caller-supplied ref into Git's option-parsing position. `watch` accepted commands beyond its documented actions. | Resolve a commit ID first and pass a fixed revision range. Restrict watch to validation and rendering and terminate file argument parsing. |

The regression suite covers issue imports to filenames containing apostrophes in JSON, YAML and TOML, safe-write decisions, unusual filenames, scan roots, envelope checksums for all supported source formats, oversized raw JSON in batch validation, permission preservation, status update through an in-project symlink, failed updates that leave the original byte-for-byte intact, and temporary directories containing apostrophes. Existing tests cover CI annotations, normal output formats, strict validation, and compatibility of structured receipts.

## Compatibility and audit coverage

Public schema, configuration variables, JSON fields, normal successful CLI receipts, and supported spec formats remain unchanged. Discovery is scoped to the current project. Invalid changelog refs fail explicitly. A status update now needs permission to create a staged replacement beside the resolved file and replaces its inode. Existing symlinks continue pointing to the updated file. GitHub import requires `gh` as before.

The audit covered CLI routing and documented exit contracts, path and symlink handling, cache and temporary state, parser limits, concurrent updates, subprocess arguments, generated GitHub annotations, package assets, CI permissions and checksums, and agent-facing export boundaries. Agent and Eval exports carry user-authored instructions and declared checks as data. Execution authority remains with their consumers. Discovery and CLI receipts remain batch-oriented, with no model calls, MCP tool-schema registration, or workflow replay in the audited runtime. General refactoring, runtime internals, release publication, and token, memory, or binary-size benchmarking were outside the security scope. The runtime, GitHub CLI and package dependency surface remained the same as the integration baseline.

## Verification

| Check | Integration baseline | Final |
| --- | --- | --- |
| `bash tests/run_tests.sh` | 112 passed | 113 passed |
| `bash tests/benchmark.sh` | 100 JSON specs in 2.04 s | 100 JSON specs in 0.81 s |
| `bash scripts/verify_docs_command_parity.sh` | 31 passed | 31 passed |
| `bash scripts/verify_completion_parity.sh` | 132 passed | 132 passed |
| `bash scripts/verify_test_runtime_parity.sh` | 3 passed | 3 passed |
| `bash scripts/release_quality_gates.sh` | 20 passed | 20 passed |
| `bash scripts/supply_chain_policy_check.sh` | 13 passed | 13 passed |

The checksum-verified runtime was provisioned with `bash .github/scripts/install-kujo-runtime.sh 1.1.0 <temporary-bin-dir>`. Shell syntax checks with `bash -n`, Python AST parsing, `git diff --check`, `scripts/spec doctor`, `scripts/spec version --json`, and `scripts/generate_command_inventory.sh --check` passed. The local-source shell installer passed strict validation through the installed launcher. `npm pack --dry-run --json` listed the launcher, Python helper, and command module.

The 100-file timings are budget observations from one run per tree under this workstation's load.

## Remaining boundaries

The command guards assume the caller controls the workspace and its temporary directory. A party that can concurrently replace filesystem path components is outside that threat model. Spec runs its runtime with the caller's permissions. No cross-repository change is needed for the fixes in this audit.
