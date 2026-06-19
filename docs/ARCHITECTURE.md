# Spec Architecture

## Overview

Spec is a structured task definition format for AI-native development in the Kujo ecosystem. It provides a standard way to describe software tasks that both humans and AI agents can understand.

## Architecture

```
┌─────────────────────────────────────────────┐
│                  spec CLI                    │
│              (scripts/spec)                  │
│         Bash wrapper + orchestration         │
└──────────┬──────────┬──────────┬────────────┘
           │          │          │
    ┌──────▼──┐ ┌─────▼───┐ ┌───▼────────┐
    │ YAML/   │ │ Kujo    │ │ Kujo       │
    │ TOML    │ │ Valid.  │ │ Render/    │
    │ Parser  │ │ Module  │ │ Export     │
    │ (Python)│ │         │ │ Modules    │
    └────┬────┘ └────┬────┘ └────┬───────┘
         │           │           │
         ▼           ▼           ▼
    ┌─────────────────────────────────────┐
    │            JSON (internal)          │
    │         parse_json / to_json        │
    └─────────────────────────────────────┘
```

## Component Design

### 1. CLI Wrapper (`scripts/spec`)

Bash script that:
- Routes commands (init, validate, render, export, version, help)
- Sources modular handlers from `scripts/commands/maintenance.sh` for operational commands (`ci`, `template`, `doctor`, `changelog`, `graph`, etc.)
- Converts YAML/TOML to JSON using Python (with fallback parser)
- Delegates validation, rendering, and export to Kujo modules
- Provides consistent CLI UX across all commands

### 2. Validation Module (`src/validate.kujo`)

Kujo script that:
- Reads a JSON spec file
- Validates against the Spec schema (required fields, types, enum values)
- Outputs JSON: `{"valid": true/false, "errors": [...], "warnings": [...]}`

### 3. Render Module (`src/render.kujo`)

Kujo script that:
- Reads a JSON spec file
- Renders it as structured Markdown
- All spec sections become Markdown headings and tables
- Outputs Markdown to stdout

### 4. Export Module (`src/export.kujo`)

Kujo script that:
- Reads a JSON spec file
- Exports as AI agent context prompt (structured text)
- Supports two formats: `agent` (full context) and `dispatch` (summary JSON)
- Agent context includes instructions for the agent

### 4b. Shared Helpers Module (`src/common.kujo`)

Kujo module that:
- Centralizes reusable helpers (for example, defaults and shared transforms)
- Is imported by `validate.kujo`, `render.kujo`, and `export.kujo`
- Keeps behavior consistent across command surfaces

### 5. Schema (`schema/spec.schema.json`)

JSON Schema (draft-07) defining the structure of spec files.

## Data Flow

```
User writes .spec.yml
        │
        ▼
spec CLI (Bash)
        │
        ├── spec_to_json() → Python YAML parser → temp .json
        │
        ▼
kujo run src/validate.kujo --json <temp>
        │
        ├── parse_json() → dict
        ├── validate_spec() → {valid, errors, warnings}
        └── to_json() → stdout
        │
        ▼
spec CLI parses result, reports PASS/FAIL
```

## Design Decisions

1. **JSON as internal format**: Kujo's `parse_json` builtin is the most reliable way to ingest structured data. YAML/TOML are converted to JSON externally.

2. **Shell script wrapper**: Bash provides process management, file I/O, and Python integration that Kujo's runtime doesn't yet support.

3. **Kujo for core logic**: Validation, rendering, and export run in Kujo for ecosystem consistency and future compatibility.

4. **Python for YAML/TOML**: The Kujo runtime doesn't have YAML/TOML parsers. Python's `yaml` library is battle-tested and widely available.

5. **No type() in conditions**: Kujo runtime v1.0.0 has known quirks with `type()` checks in conditional branches. The modules use `has_key()` instead.

## Compatibility Matrix

| Component | Supported | Notes |
|---|---|---|
| Shell | Bash 3.2+ | macOS default Bash is supported (no Bash 4 associative arrays required) |
| Kujo runtime | Kujo language runtime with module import support | Set `KUJO_BIN` to the runtime binary |
| Python | Python 3.8+ | Used for YAML/TOML conversion helpers |
| YAML parser | `pyyaml` preferred | Fallback parser supports documented subset |
| TOML parser | stdlib `tomllib` or fallback parser | Nested tables remain out of scope |

Unsupported assumptions:
- Running CLI commands from outside the repository root while relying on relative module resolution.
- Cross-repository Kujo module imports outside the trusted project tree.

## Security Model

- All spec processing is local (no network calls)
- File size limited to 1MB
- JSON parsing uses Kujo's builtin (safe)
- YAML parsing uses Python's `yaml.safe_load()` (safe)
- No eval/exec of spec content
- No API keys or secrets in spec files by design
- File reads are restricted to the current project tree and reject path traversal plus symlink escapes.
- Output writes can be restricted with `SPEC_SAFE_WRITE=on`; `--unsafe-write` is an explicit override.
- User-home templates can be blocked with `SPEC_TEMPLATE_SOURCE_POLICY=project-only` or `--strict-template-source`.
- Conversion caching uses canonical file paths and content-aware signatures so stale or colliding cache entries are not reused.
