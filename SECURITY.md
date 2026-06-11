# Security Policy — Spec

## Security Model

Spec reads user-provided spec files (YAML, TOML, JSON) and validates them against a JSON Schema. It also executes shell commands indirectly through the Kujo runtime for validation, rendering, and export operations. The following protections are in place:

### 1. Command Injection Prevention (SEC-01 — fixed v0.1.0)

Filenames are passed to Python parsers via `sys.argv` (not string interpolation), eliminating the command injection vector that existed in earlier inline Python code.

### 2. Path Traversal Protection (SEC-02 — fixed v0.1.0)

The `is_safe_path()` function blocks:
- Paths containing `..` directory traversal
- Absolute paths outside the current working directory

Symlink trust boundary policy:
- Symlinks are allowed only when their resolved target remains inside the current project directory.
- Symlinks that resolve outside the project root are denied.

### 3. Input Sanitization (SEC-03 — fixed v0.1.0)

The `--name` parameter in `spec init` is validated against a safe character class (`[a-zA-Z0-9 _-]+`), rejecting quotes, backticks, and other special characters.

### 4. File Size Limiting

The Kujo validate module enforces a 1MB maximum file size before parsing spec content.

### 5. YAML Safe Loading

When PyYAML is available, `yaml.safe_load()` is used (not `yaml.load()`), preventing arbitrary code execution via YAML tags.

### 6. Output Path Guardrails

When safe-write mode is enabled (`SPEC_SAFE_WRITE=on` or `auto` in `spec ci` context), output-producing commands restrict writes to the current project directory.

- Blocked by default: output paths outside project root (including resolved symlink escapes)
- Allowed by explicit intent: pass `--unsafe-write` to override for a single command

## Known Limitations

- **YAML parsing**: The fallback parser (used when PyYAML isn't available) handles only a basic subset of YAML. Complex YAML features (anchors, tags, multi-document) are not supported and will cause parse errors.
- **TOML parsing**: Similarly limited fallback parser when `tomllib`/`tomli` isn't available.
- **Kujo runtime**: The validate/render/export modules run via the Kujo language runtime, which may have its own security characteristics.
- **No sandboxing**: Spec processing runs with the user's full permissions. Filesystem access is required for reading spec files.
- **Temp files**: Temporary JSON files are created during processing (via `mktemp`). These are cleaned up on script exit.
- **Path boundary scope**: Path checks are anchored to the caller's current working directory; run commands from the intended project root for strictest boundaries.

## Reporting a Vulnerability

To report a security issue, please open an issue on the GitHub repository at:
https://github.com/kujolang/spec

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

## Responsible Disclosure

Please allow reasonable time for fixes before public disclosure. Security issues will be addressed as priority.
