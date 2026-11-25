#!/usr/bin/env python3
"""Spec helper — fast field extraction from spec JSON files.

Usage:
  python3 spec_helpers.py get <json-file> <field> [default]
  python3 spec_helpers.py count <json-file> <array-field>
  python3 spec_helpers.py fields <json-file> <field1,field2,...>
  python3 spec_helpers.py dump <json-file>

All file paths are passed via sys.argv (never string-interpolated into code),
eliminating command injection risk from spec file paths.
"""
import json
import os
import sys

KNOWN_CHECK_TYPES = {
    "command_succeeds", "command_output_contains", "file_exists",
    "file_contains", "file_line_count", "json_path_value",
    "snapshot_matches", "directory_contains_files", "regex_matches",
    "command_timing_less_than", "env_var_set", "http_status",
    "http_body_contains", "markdown_contains_section", "exit_code",
    "stdout_contains", "stderr_empty", "artifact_exists",
}

VALID_PRIORITIES = {"critical", "high", "medium", "low"}
VALID_SEVERITIES = {"low", "medium", "high", "critical"}
VALID_STATUSES = {"draft", "ready", "in-progress", "review", "completed", "archived"}
KNOWN_TOP_LEVEL_FIELDS = {
    "name", "goal", "id", "status", "version", "created_at",
    "updated_at", "completed_at", "estimated_hours", "children", "metadata",
    "background", "scope", "non_goals", "relevant_systems", "likely_files",
    "acceptance_criteria", "eval_requirements", "risks", "dependencies",
    "review_expectations", "human_approval_points", "estimated_effort",
    "priority", "assignee", "tags", "parent_id",
}


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def safe_read_path(path):
    """Check the lexical path and the resolved target against the project root."""
    cwd = os.getcwd()
    if ".." in path:
        message = f"Error: Path traversal detected in: {path}"
    else:
        absolute = os.path.abspath(path)
        if absolute != cwd and not absolute.startswith(cwd + "/"):
            message = f"Error: Access to path outside project denied: {path}"
        else:
            resolved = os.path.realpath(path) if os.path.exists(path) else absolute
            if resolved == cwd or resolved.startswith(cwd + "/"):
                return True
            print(f"Error: Symlink target outside project denied: {path}", file=sys.stderr)
            print(f"Resolved target: {resolved}", file=sys.stderr)
            return False
    print(message, file=sys.stderr)
    print("Spec files must be within the current project directory.", file=sys.stderr)
    return False


def validate_ci_json(filepath, strict):
    if not safe_read_path(filepath):
        return 1
    try:
        if os.path.getsize(filepath) > 1048576:
            return 1
        return validate_quiet(filepath, strict)
    except (OSError, ValueError, TypeError, RecursionError):
        # CI reports the failing file and leaves detailed diagnostics to validate.
        return 1


def field_text(value):
    return json.dumps(value) if isinstance(value, (list, dict)) else str(value)


def fields_text(spec, fields):
    return "|".join(
        " ".join(str(item) for item in value) if isinstance(value, list) else field_text(value)
        for value in (spec.get(field, "") for field in fields)
    )


def read_metadata(filepath):
    try:
        with open(filepath) as fh:
            spec = json.load(fh)
        if isinstance(spec, dict):
            return spec
    except (OSError, ValueError, RecursionError):
        pass
    return None


def write_fields(*values):
    # Bash traditionally discards NULs and trailing newlines from substitutions.
    for value in values:
        sys.stdout.write(value.replace("\0", "").rstrip("\n") + "\0")


def info_fields(filepath):
    fields = ("name", "goal", "status", "priority", "version", "id")
    spec = read_metadata(filepath)
    if spec is None:
        write_fields("|" * (len(fields) - 1), "0", "0", "0", "0", "")
        return
    arrays = ("acceptance_criteria", "dependencies", "eval_requirements", "risks")
    counts = [str(len(value)) if isinstance(value, list) else "0"
              for value in (spec.get(key) for key in arrays)]
    write_fields(fields_text(spec, fields), *counts, field_text(spec.get("tags", "")))


def search_fields(filepath):
    spec = read_metadata(filepath) or {}
    write_fields(*(field_text(spec.get(key, "")) for key in ("name", "priority", "tags")))


def render_graph(output_format, filepaths):
    nodes = []
    by_id = {}
    for filepath in filepaths:
        spec = read_metadata(filepath) or {}
        name, parent, spec_id = (
            field_text(spec.get(key, default)).replace("\0", "").rstrip("\n")
            for key, default in (("name", "?"), ("parent_id", ""), ("id", ""))
        )
        by_id.setdefault(spec_id, len(nodes))
        nodes.append((json.dumps(name), parent))

    if output_format == "mermaid":
        print("```mermaid")
        print("graph TD")
        for index, (label, parent) in enumerate(nodes):
            print(f"    spec{index}[{label}]")
            if parent and parent in by_id:
                print(f"    spec{by_id[parent]} --> spec{index}")
        print("```")
    else:
        print("digraph Specs {")
        print("  rankdir=TB;")
        print("  node [shape=box, style=rounded];")
        for index, (label, _) in enumerate(nodes):
            print(f"  spec{index} [label={label}];")
        for index, (_, parent) in enumerate(nodes):
            if parent and parent in by_id:
                print(f"  spec{by_id[parent]} -> spec{index};")
        print("}")


def validation_result(filepath, strict, json_out, quiet):
    raw_result = sys.stdin.read()
    try:
        result = json.loads(raw_result)
    except ValueError:
        result = {"valid": False, "errors": ["Validation output parse error"], "warnings": []}

    valid = False
    if isinstance(result, dict):
        warnings = result.get("warnings")
        if not isinstance(warnings, list):
            warnings = result["warnings"] = []
        spec = read_metadata(filepath) or {}
        for key in spec:
            if key not in KNOWN_TOP_LEVEL_FIELDS:
                message = f"Unknown top-level field: {key}"
                if message not in warnings:
                    warnings.append(message)
        valid = str(result.get("valid")) == "True" and not (strict and warnings)
        result["valid"] = valid

    if json_out:
        print(json.dumps(result) if isinstance(result, dict) else raw_result.rstrip("\n"))
    elif valid:
        if not quiet:
            print("PASS: Spec is valid")
    else:
        print("FAIL: Validation failed")
        if isinstance(result, dict):
            for error in result.get("errors", []):
                print("  - " + error)
            if strict:
                for warning in result["warnings"]:
                    print("  WARNING: " + warning)
    return 0 if valid else 1


def get_field(filepath, field, default=""):
    try:
        with open(filepath) as fh:
            d = json.load(fh)
        val = d.get(field, default)
        if isinstance(val, (list, dict)):
            print(json.dumps(val))
        else:
            print(val)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(default)


def count_field(filepath, field):
    try:
        with open(filepath) as fh:
            d = json.load(fh)
        arr = d.get(field, [])
        print(len(arr) if isinstance(arr, list) else 0)
    except (FileNotFoundError, json.JSONDecodeError):
        print(0)


def get_fields(filepath, *fields):
    """Output space-separated values for multiple fields."""
    try:
        with open(filepath) as fh:
            d = json.load(fh)
        print(fields_text(d, fields))
    except (FileNotFoundError, json.JSONDecodeError):
        print("|".join("" for _ in fields))


def dump_json(filepath):
    """Print the full JSON content (for piping to other commands)."""
    try:
        with open(filepath) as fh:
            print(fh.read())
    except FileNotFoundError:
        fail(f"File not found: {filepath}")


def list_specs(filepaths, json_out=False):
    """Output spec summaries for multiple files. Uses a single Python process."""
    results = []
    for fp in filepaths:
        if not fp.strip():
            continue
        try:
            with open(fp) as fh:
                d = json.load(fh)
            name = d.get("name", "?")
            priority = d.get("priority", "?")
            status = d.get("status", "draft")
            if json_out:
                results.append({"file": fp, "name": name, "priority": priority, "status": status})
            else:
                results.append((fp, priority, name, status))
        except (FileNotFoundError, json.JSONDecodeError):
            if json_out:
                results.append({"file": fp, "name": "?", "priority": "?", "status": "?"})
            else:
                results.append((fp, "?", "?", "?"))

    if json_out:
        print(json.dumps(results, indent=2))
    else:
        # Output TSV for shell parsing
        for row in results:
            print("|".join(row))


def validate_quiet(filepath, strict=False):
    """Fast batch validator matching the runtime validator's pass/fail rules."""
    try:
        with open(filepath) as fh:
            spec = json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        return 1

    if not isinstance(spec, dict):
        return 1

    errors = []
    warnings = []

    name = spec.get("name", "")
    if not isinstance(name, str) or name == "":
        errors.append("Missing required field: name")
    elif len(name) > 200:
        errors.append("Field name exceeds 200 characters")

    goal = spec.get("goal", "")
    if not isinstance(goal, str) or goal == "":
        errors.append("Missing required field: goal")
    elif len(goal) > 5000:
        errors.append("Field goal exceeds 5000 characters")

    string_limits = {
        "background": 10000,
        "scope": 10000,
        "estimated_effort": 200,
        "assignee": 200,
    }
    for key in ("version", "id", "status", "created_at", "updated_at", "completed_at",
                "background", "scope", "estimated_effort", "assignee", "parent_id"):
        if key in spec and not isinstance(spec[key], str):
            errors.append(f"Field {key} must be a string, got non-string value")
        elif key in spec and key in string_limits and len(spec[key]) > string_limits[key]:
            errors.append(f"Field {key} exceeds {string_limits[key]} characters")

    max_items = {
        "non_goals": 100,
        "relevant_systems": 50,
        "likely_files": 200,
        "acceptance_criteria": 100,
        "review_expectations": 50,
        "human_approval_points": 50,
        "tags": 50,
        "children": 200,
    }
    item_limits = {
        "non_goals": 2000,
        "relevant_systems": 500,
        "likely_files": 1000,
        "acceptance_criteria": 2000,
        "review_expectations": 1000,
        "human_approval_points": 1000,
        "tags": 200,
    }
    for key, limit in max_items.items():
        if key not in spec:
            continue
        value = spec[key]
        if not isinstance(value, list):
            errors.append(f"Field {key} must be an array")
            continue
        if len(value) > limit:
            errors.append(f"Field {key} exceeds maximum of {limit} items")
        if key == "acceptance_criteria" and not value:
            errors.append("Field acceptance_criteria requires at least 1 item")
        for idx, item in enumerate(value):
            if not isinstance(item, str):
                errors.append(f"Field {key}[{idx}] must be a string")
            elif key in item_limits and len(item) > item_limits[key]:
                errors.append(f"Field {key}[{idx}] exceeds {item_limits[key]} characters")

    status = spec.get("status")
    if isinstance(status, str) and status not in VALID_STATUSES:
        errors.append("Invalid status: " + status + " (use draft/ready/in-progress/review/completed/archived)")

    spec_id = spec.get("id")
    if isinstance(spec_id, str):
        import re
        if re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", spec_id) is None:
            errors.append("Field id must be a UUID v4")

    if "estimated_hours" in spec and (isinstance(spec["estimated_hours"], bool) or not isinstance(spec["estimated_hours"], (int, float))):
        errors.append("Field estimated_hours must be a number")
    if "metadata" in spec and not isinstance(spec["metadata"], dict):
        errors.append("Field metadata must be an object")

    dependencies = spec.get("dependencies", [])
    if "dependencies" in spec:
        if not isinstance(dependencies, list):
            errors.append("Field dependencies must be an array")
        else:
            if len(dependencies) > 100:
                errors.append("Field dependencies exceeds maximum of 100 items")
            for idx, dep in enumerate(dependencies):
                if isinstance(dep, dict):
                    if not isinstance(dep.get("description"), str):
                        errors.append(f"dependencies[{idx}] must have a string description")
                    elif len(dep["description"]) > 2000:
                        errors.append(f"dependencies[{idx}].description exceeds 2000 characters")
                    if "type" in dep and dep["type"] not in {"blocks", "blocked_by"}:
                        errors.append(f"dependencies[{idx}].type must be blocks or blocked_by")
                    if "spec_id" in dep and not isinstance(dep["spec_id"], str):
                        errors.append(f"dependencies[{idx}].spec_id must be a string")
                elif not isinstance(dep, str):
                    errors.append(f"dependencies[{idx}] must be a string or object")

    eval_requirements = spec.get("eval_requirements", [])
    if "eval_requirements" in spec:
        if not isinstance(eval_requirements, list):
            errors.append("Field eval_requirements must be an array")
        else:
            if len(eval_requirements) > 200:
                errors.append("Field eval_requirements exceeds 200 items")
            for idx, er in enumerate(eval_requirements):
                if not isinstance(er, dict):
                    errors.append(f"eval_requirements[{idx}] must be an object")
                    continue
                description = er.get("description")
                if not isinstance(description, str):
                    errors.append(f"eval_requirements[{idx}] must have a string description")
                elif len(description) > 2000:
                    errors.append(f"eval_requirements[{idx}].description exceeds 2000 characters")
                check_type = er.get("check_type", "")
                if not isinstance(check_type, str):
                    errors.append(f"eval_requirements[{idx}].check_type must be a string")
                elif check_type and check_type not in KNOWN_CHECK_TYPES:
                    warnings.append(f"Unknown check_type: {check_type}")
                if "params" in er and not isinstance(er["params"], dict):
                    errors.append(f"eval_requirements[{idx}].params must be an object")
                if "tags" in er:
                    tags = er["tags"]
                    if not isinstance(tags, list) or any(not isinstance(tag, str) for tag in tags):
                        errors.append(f"eval_requirements[{idx}].tags must be an array of strings")

    risks = spec.get("risks", [])
    if "risks" in spec:
        if not isinstance(risks, list):
            errors.append("Field risks must be an array")
        else:
            if len(risks) > 100:
                errors.append("Field risks exceeds 100 items")
            for idx, risk in enumerate(risks):
                if not isinstance(risk, dict):
                    errors.append(f"risks[{idx}] must be an object")
                    continue
                if "risk" not in risk:
                    errors.append(f"risks[{idx}] missing risk field")
                elif not isinstance(risk["risk"], str):
                    errors.append(f"risks[{idx}].risk must be a string")
                elif len(risk["risk"]) > 2000:
                    errors.append(f"risks[{idx}].risk exceeds 2000 characters")
                if "mitigation" in risk and not isinstance(risk["mitigation"], str):
                    errors.append(f"risks[{idx}].mitigation must be a string")
                elif "mitigation" in risk and len(risk["mitigation"]) > 2000:
                    errors.append(f"risks[{idx}].mitigation exceeds 2000 characters")
                severity = risk.get("severity")
                if severity is not None and not isinstance(severity, str):
                    errors.append(f"risks[{idx}].severity must be a string")
                elif severity is not None and severity not in VALID_SEVERITIES:
                    warnings.append(f"Invalid severity: {severity}")

    priority = spec.get("priority", "medium")
    if not isinstance(priority, str) or priority not in VALID_PRIORITIES:
        errors.append(f"Invalid priority: {priority} (use critical/high/medium/low)")

    for key in spec:
        if key not in KNOWN_TOP_LEVEL_FIELDS:
            warnings.append(f"Unknown top-level field: {key}")

    if errors or (strict and warnings):
        return 1
    return 0


def validate_many(strict, filepaths):
    passed = 0
    failed = 0
    for filepath in filepaths:
        if validate_quiet(filepath, strict) == 0:
            passed += 1
        else:
            failed += 1
    print(f"{passed}|{failed}")
    return 0 if failed == 0 else 1


def main():
    if len(sys.argv) < 2:
        fail("Usage: spec_helpers.py <command> [args...]")

    cmd = sys.argv[1]

    if cmd == "get":
        if len(sys.argv) < 4:
            fail("Usage: spec_helpers.py get <json-file> <field> [default]")
        default = sys.argv[4] if len(sys.argv) > 4 else ""
        get_field(sys.argv[2], sys.argv[3], default)

    elif cmd == "count":
        if len(sys.argv) < 4:
            fail("Usage: spec_helpers.py count <json-file> <array-field>")
        count_field(sys.argv[2], sys.argv[3])

    elif cmd == "fields":
        if len(sys.argv) < 4:
            fail("Usage: spec_helpers.py fields <json-file> <field1,field2,...>")
        get_fields(sys.argv[2], *sys.argv[3:])

    elif cmd == "dump":
        if len(sys.argv) < 3:
            fail("Usage: spec_helpers.py dump <json-file>")
        dump_json(sys.argv[2])

    elif cmd == "list":
        # Usage: spec_helpers.py list [--json] <file1> <file2> ...
        json_out = False
        args = sys.argv[2:]
        if args and args[0] == "--json":
            json_out = True
            args = args[1:]
        if not args:
            fail("Usage: spec_helpers.py list [--json] <file1> <file2> ...")
        list_specs(args, json_out)

    elif cmd == "info-fields":
        info_fields(sys.argv[2])

    elif cmd == "search-fields":
        search_fields(sys.argv[2])

    elif cmd == "graph":
        paths = (os.fsdecode(path) for path in sys.stdin.buffer.read().split(b"\0") if path)
        render_graph(sys.argv[2], paths)

    elif cmd == "validation-result":
        flags = [arg == "true" for arg in sys.argv[3:6]]
        sys.exit(validation_result(sys.argv[2], *flags))

    elif cmd == "safe-path":
        sys.exit(0 if safe_read_path(sys.argv[2]) else 1)

    elif cmd == "validate-ci-json":
        sys.exit(validate_ci_json(sys.argv[2], sys.argv[3] == "true"))

    elif cmd == "validate-quiet":
        if len(sys.argv) < 3:
            fail("Usage: spec_helpers.py validate-quiet <json-file> [strict=true|false]")
        strict = len(sys.argv) > 3 and sys.argv[3].lower() == "true"
        sys.exit(validate_quiet(sys.argv[2], strict))

    elif cmd == "validate-many":
        if len(sys.argv) < 4:
            fail("Usage: spec_helpers.py validate-many <strict=true|false> <json-file> [...]")
        strict = sys.argv[2].lower() == "true"
        sys.exit(validate_many(strict, sys.argv[3:]))

    else:
        fail(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()
