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
        results = []
        for field in fields:
            val = d.get(field, "")
            if isinstance(val, list):
                results.append(" ".join(str(v) for v in val))
            elif isinstance(val, dict):
                results.append(json.dumps(val))
            else:
                results.append(str(val))
        print("|".join(results))
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
    import os
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

    for key in ("version", "id", "status", "created_at", "updated_at", "completed_at",
                "background", "scope", "estimated_effort", "assignee"):
        if key in spec and not isinstance(spec[key], str):
            errors.append(f"Field {key} must be a string, got non-string value")

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
    for key, limit in max_items.items():
        if key not in spec:
            continue
        value = spec[key]
        if not isinstance(value, list):
            errors.append(f"Field {key} must be an array")
            continue
        if len(value) > limit:
            errors.append(f"Field {key} exceeds maximum of {limit} items")
        for idx, item in enumerate(value):
            if not isinstance(item, str):
                errors.append(f"Field {key}[{idx}] must be a string")

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
                if "description" not in er:
                    errors.append(f"eval_requirements[{idx}] missing description")
                check_type = er.get("check_type", "")
                if check_type and check_type not in KNOWN_CHECK_TYPES:
                    warnings.append(f"Unknown check_type: {check_type}")

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
                if "mitigation" in risk and not isinstance(risk["mitigation"], str):
                    errors.append(f"risks[{idx}].mitigation must be a string")
                severity = risk.get("severity")
                if severity is not None and not isinstance(severity, str):
                    errors.append(f"risks[{idx}].severity must be a string")
                elif severity is not None and severity not in VALID_SEVERITIES:
                    warnings.append(f"Invalid severity: {severity}")

    priority = spec.get("priority", "medium")
    if priority not in VALID_PRIORITIES:
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
