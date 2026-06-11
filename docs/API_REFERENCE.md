# Spec API Reference

## CLI Commands

### Command Summary

The command inventory is generated from `spec help` and maintained in one place:

- `docs/COMMAND_INVENTORY.md`

Regenerate after CLI changes:

```bash
bash scripts/generate_command_inventory.sh write
```

### Common Syntax

```bash
spec init [--format yaml|toml|json] [--output <path>] [--name <name>] [--from <source>]
spec validate <spec-file> [--quiet] [--strict] [--json]
spec render <spec-file> [--output <path>]
spec export <spec-file> [--format agent|dispatch|markdown|eval] [--output <path>]
spec list [--dir <path>] [--json] [--max-depth <n>]
spec ci [<directory>] [--strict] [--format text|json|github]
spec graph [<directory>] [--format mermaid|dot]
```

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Failure/validation error/usage error |

## JSON Output Contracts

### `spec version --json`

```json
{
	"version": "0.1.0",
	"contract": "0.1.0",
	"schema_version": "1.0.0"
}
```

### `spec validate --json`

```json
{
	"valid": true,
	"errors": [],
	"warnings": []
}
```

### `spec ci --format json`

```json
{
	"total": 2,
	"passed": 2,
	"failed": 0,
	"failures": []
}
```

## Kujo Module API

### `src/validate.kujo`

Input:

```bash
kujo run src/validate.kujo --json <path-to-json-file>
```

Output:

```json
{"valid": true|false, "errors": [...], "warnings": [...]} 
```

### `src/render.kujo`

Input:

```bash
kujo run src/render.kujo --json <path-to-json-file>
```

Output: Markdown string to stdout.

### `src/export.kujo`

Input:

```bash
kujo run src/export.kujo --json <path-to-json-file> [--format agent|dispatch]
```

Output: Agent context text or dispatch JSON string.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `KUJO_BIN` | `kujo` | Kujo language runtime executable/path |
| `SPEC_TIMEOUT` | `30` | Timeout in seconds for Kujo subprocess invocation |

## Schema Reference

See [../schema/spec.schema.json](../schema/spec.schema.json) for the complete JSON Schema.
