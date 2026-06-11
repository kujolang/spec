#!/usr/bin/env python3
"""Convert a TOML spec file to JSON. Writes JSON to stdout.

Usage: python3 spec_toml_to_json.py <input-file>

The input file path is received via sys.argv (NOT string interpolation),
eliminating the command injection vector present in inline Python.

Exit codes:
  0 — success, JSON written to stdout
  1 — parse error or file not found
"""
import json
import sys
import os


def parse_basic_toml(filepath: str) -> dict:
    """Fallback parser for simple key=value TOML when tomllib/tomli is unavailable."""
    data: dict = {}

    with open(filepath, "r") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if "=" in s:
                k, _, v = s.partition("=")
                k = k.strip()
                v = v.strip().strip('"')
                if v == "true":
                    v = True
                elif v == "false":
                    v = False
                elif v == "[]":
                    v = []
                data[k] = v

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
        import tomllib  # type: ignore
        with open(filepath, "rb") as fh:
            data = tomllib.load(fh)
    except ImportError:
        try:
            import tomli  # type: ignore
            with open(filepath, "rb") as fh:
                data = tomli.load(fh)
        except ImportError:
            data = parse_basic_toml(filepath)

    if data is None:
        data = {}

    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
