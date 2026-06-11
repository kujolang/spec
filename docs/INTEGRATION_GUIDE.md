# Integration Guide

How to use Spec with other Kujo ecosystem tools.

## kujo-eval

Spec's `eval_requirements` field maps directly to eval test definitions. Use `spec export-eval` to generate a runnable eval suite.

### Workflow

```bash
# 1. Create a spec with eval requirements
spec init --name "cli-quality-gate" --output cli-quality.spec.yml

# Fill in eval_requirements in the spec:
# eval_requirements:
#   - description: "Help command succeeds"
#     check_type: "command_succeeds"
#     params:
#       command: "my-cli help"
#   - description: "Version outputs expected string"
#     check_type: "command_output_contains"
#     params:
#       command: "my-cli version"
#       expected: "v1.0.0"

# 2. Export as an eval suite
spec export-eval cli-quality.spec.yml --output eval_suite.json

# 3. Run with kujo-eval
eval run eval_suite.json
```

### Mapping Spec Fields to Eval

| Spec Field | Eval Field | Notes |
|---|---|---|
| `name` | `suite.name` | Suite identifier |
| `goal` | `suite.description` | Suite description |
| `eval_requirements[].description` | `test.name` | Test name |
| `eval_requirements[].check_type` | `test.check` | Eval check function name |
| `eval_requirements[].params` | `test.params` | Passed through unchanged |

### Supported Check Types

The validator recognizes these check types (see `KNOWN_CHECK_TYPES` in `src/validate.kujo`):

- `command_succeeds` — Exit code 0
- `command_output_contains` — stdout contains string
- `file_exists` — File at path exists
- `file_contains` — File contains string
- `file_line_count` — File has expected line count
- `json_path_value` — JSON path has expected value
- `snapshot_matches` — Output matches snapshot
- `directory_contains_files` — Directory has expected files
- `regex_matches` — Output matches regex
- `command_timing_less_than` — Command runs within time limit
- `env_var_set` — Environment variable is set
- `http_status` — HTTP endpoint returns expected status
- `http_body_contains` — HTTP response body contains string
- `markdown_contains_section` — Markdown has expected section
- `exit_code` — Specific exit code
- `stdout_contains` — stdout contains string
- `stderr_empty` — stderr is empty
- `artifact_exists` — Build artifact exists

## kujo-dispatch

Export specs as dispatch work units for automated task distribution.

### Workflow

```bash
# Export a spec as a dispatch-compatible work unit
spec export-agent-context my-feature.spec.yml --format dispatch --output work-unit.json

# The output includes:
# - name: spec name
# - goal: spec goal
# - priority: mapped to dispatch urgency
# - ac_count: number of acceptance criteria
# - dep_count: number of dependencies
```

### Priority Mapping

| Spec Priority | Dispatch Urgency |
|---|---|
| `critical` | `urgent` |
| `high` | `high` |
| `medium` | `normal` |
| `low` | `low` |

## kujo-scout

Specs can be scouted (discovered and indexed) by kujo-scout for project-wide visibility.

### Making Specs Scoutable

1. Place spec files in a `specs/` directory at the project root
2. Ensure each spec has a `tags` field for categorization
3. Use `spec status` to keep lifecycle state current

### Scout Query Examples

```bash
# Find all ready-to-implement specs
spec search --tag ready

# Find high-priority security specs
spec search --priority high --tag security

# Find specs awaiting review
spec status --filter review
```

## kujo-mcp

Expose spec tools through an MCP (Model Context Protocol) server for AI agent integration.

### Available Tools

When integrated with kujo-mcp, the following spec operations become available to AI agents:

- `spec.validate` — Validate a spec file
- `spec.render` — Render spec to Markdown
- `spec.export_agent_context` — Export spec as agent context
- `spec.list` — List all specs in a project
- `spec.search` — Search specs by criteria

### MCP Server Configuration

```json
{
  "mcpServers": {
    "kujo-spec": {
      "command": "spec",
      "args": ["mcp-serve"],
      "env": {
        "KUJO_BIN": "/path/to/kujo"
      }
    }
  }
}
```

## kujo-kennel

Spec is registered as a kennel package. Other packages can depend on it:

```toml
# In your kennel.toml
[dependencies]
spec = { version = "0.1.0" }
```

This makes the spec validation, rendering, and export modules available for import in other Kujo projects.
