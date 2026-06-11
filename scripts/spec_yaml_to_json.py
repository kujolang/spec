#!/usr/bin/env python3
"""Convert a YAML spec file to JSON. Writes JSON to stdout.

Usage: python3 spec_yaml_to_json.py <input-file>

The input file path is received via sys.argv (NOT string interpolation),
eliminating the command injection vector present in inline Python.

Exit codes:
  0 — success, JSON written to stdout
  1 — parse error or file not found
"""
import json
import sys
import os


def parse_basic_yaml(filepath: str) -> dict:
    """Fallback parser for simple key:value YAML when PyYAML is unavailable."""
    data: dict = {}
    curr_key = None
    curr_list: list = []

    with open(filepath, "r") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("- "):
                item = s[2:].strip().strip('"')
                if curr_key is not None:
                    curr_list.append(item)
                continue
            if ":" in s:
                if curr_key is not None and curr_list:
                    data[curr_key] = curr_list
                    curr_key = None
                    curr_list = []
                k, _, v = s.partition(":")
                k = k.strip()
                v = v.strip().strip('"')
                if not v:
                    curr_key = k
                    curr_list = []
                    continue
                if v == "true":
                    v = True
                elif v == "false":
                    v = False
                elif v == "[]":
                    v = []
                elif v in ("null", "~"):
                    v = ""
                data[k] = v

    if curr_key is not None and curr_list:
        data[curr_key] = curr_list

    return data


def main() -> None:
    if len(sys.argv) < 2:
        print("Error: no input file specified", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]

    if not os.path.isfile(filepath):
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    data: dict = {}

    try:
        import yaml  # type: ignore
        with open(filepath, "r") as fh:
            data = yaml.safe_load(fh)
    except ImportError:
        data = parse_basic_yaml(filepath)

    if data is None:
        data = {}

    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
