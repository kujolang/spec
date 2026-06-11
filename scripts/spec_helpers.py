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

    else:
        fail(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()
