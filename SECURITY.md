# Security Policy — Spec

## Security Model

Spec reads user-provided spec files (YAML, TOML, JSON) and validates them against a JSON Schema. It also executes shell commands indirectly through the Kujo runtime for validation, rendering, and export operations. The following protections are in place:

### 1. Command Injection Prevention (SEC-01 — fixed v0.1.0)

Filenames are passed to Kujo and Python helpers as arguments. GitHub issue imports pass the output path to a fixed serializer and terminate GitHub CLI option parsing before the issue identifier. Changelog resolves a commit before passing the resulting revision range to Git.

Spec runs its Python helpers in isolated mode. Python excludes the workspace,
`PYTHONPATH`, and user-site packages from module discovery. Optional PyYAML
support uses a package available to that interpreter in isolated mode.

### 2. Path Traversal Protection (SEC-02 — fixed v0.1.0)

The `is_safe_path()` function blocks:
- Paths containing `..` directory traversal
- Absolute paths outside the current working directory

Discovery through `list`, `graph`, `validate-all`, and `ci` also checks the requested directory. Discovery preserves filename boundaries, including embedded newlines.

Symlink trust boundary policy:
- Symlinks are allowed only when their resolved target remains inside the current project directory.
- Symlinks that resolve outside the project root are denied.

### 3. Input Sanitization (SEC-03 — fixed v0.1.0)

The `--name` parameter in `spec init` and `spec init-interactive` is validated against a safe character class (`[a-zA-Z0-9 _-]+`), rejecting quotes, backticks, and other special characters. Interactive goal and tag values are serialized as data instead of being interpolated into YAML.

### 4. File Size Limiting

Conversion and validation enforce the 1 MiB limit on source spec files, including when an in-project symlink points to a larger file. Batch JSON validation in `validate-all` and `ci` uses bounded reads.

JSON imports enforce the same limit for regular files and standard input.
They parse a JSON object before creating the destination, and preserve literal
keys when writing YAML or TOML.

### 5. Structured Data Parsing

Spec input conversion uses Kujo's `parse_yaml`, `parse_toml`, and `parse_json` functions. Spec content is never evaluated as executable code. Interactive YAML creation uses `yaml.safe_dump()` when PyYAML is available and a JSON-compatible YAML subset otherwise.

### 6. Output Path Guardrails

When safe-write mode is enabled (`SPEC_SAFE_WRITE=on` or `auto` in `spec ci` context), output-producing commands check the lexical and resolved destination against the current project directory. This check covers dangling symlinks and their eventual targets. Invalid policy values fail when the corresponding safe-write or home-template policy is consulted.

- Blocked by default: output paths outside project root (including resolved symlink escapes)
- Allowed by explicit intent: pass `--unsafe-write` to override for a single command

Lifecycle updates from `spec status --set` stage and validate a replacement before publishing it atomically. Updates through in-project symlinks replace the resolved file and preserve the symlink.

### 7. Generated Output Safety

Mermaid and DOT graph labels are escaped before untrusted spec names are embedded. GitHub CI annotations escape filename control characters and property separators. Render and export commands fail closed when the Kujo runtime fails or returns no output.

`ci` and `validate-all` reject incomplete discovery when the scanner reports
an error. Malformed dependency records count as failures for their own files.
Conversion to YAML or TOML and Eval export finish generating output before
opening the destination, so generation failures preserve existing files.

### 8. Conversion Cache Isolation

Spec creates its conversion cache directory with mode `0700`. A symlink, different owner, or group or other access disables caching for that operation. Cache misses hash and parse the same snapshot, and publish the signature and JSON together through one atomic replacement.

### 9. Container Runtime Integrity

Docker builds that download a Kujo runtime with `KUJO_BIN_URL` must also supply `KUJO_BIN_SHA256`; the build verifies the binary before making it executable.

## Known Limitations

- **YAML parsing**: Complex YAML features (anchors, tags, multi-document) are outside the supported subset and may produce parse errors.
- **TOML parsing**: Nested tables and arrays of tables remain outside the supported subset.
- **Kujo runtime**: The validate/render/export modules run via the Kujo language runtime, which may have its own security characteristics.
- **No sandboxing**: Spec processing runs with the user's full permissions. Filesystem access is required for reading spec files.
- **Temp files**: Processing uses private temporary files and directories created by `mktemp`. An interrupted process can leave scratch files behind.
- **Path boundary scope**: Path checks are anchored to the caller's current working directory. Run commands from the intended project root. Filesystem guardrails assume the caller controls the workspace and its temporary directory. They cannot guarantee containment against concurrent replacement of path components.

## Reporting a Vulnerability

To report a security issue, please open an issue on the GitHub repository at:
https://github.com/kujolang/spec

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

## Responsible Disclosure

Please allow reasonable time for fixes before public disclosure. Security issues will be addressed as priority.
