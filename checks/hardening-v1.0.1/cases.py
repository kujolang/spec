#!/usr/bin/env python3
"""Command-policy-safe entry point for the hardening outcome cases."""

from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[2]
runpy.run_path(
    str(root / "evaluation" / "hardening-v1.0.1" / "scripts" / "eval_case.py"),
    run_name="__main__",
)
