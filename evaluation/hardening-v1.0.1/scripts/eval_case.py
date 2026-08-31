#!/usr/bin/env python3
"""Execute one deterministic hardening requirement against a Spec checkout."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path


def run(
    spec: Path,
    args: list[str],
    cwd: Path,
    env: dict[str, str] | None = None,
    stdin: str | None = None,
    timeout: int = 240,
):
    environment = os.environ.copy()
    environment.update({"KUJO_BIN": os.environ.get("KUJO_BIN", "kujo"), "SPEC_TIMEOUT": "30"})
    if env:
        environment.update(env)
    return subprocess.run(
        [str(spec), *args],
        cwd=cwd,
        env=environment,
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def valid_spec() -> dict:
    return {
        "name": "Hardening evaluation",
        "goal": "Verify deterministic Spec behavior",
        "version": "1.0.0",
        "status": "ready",
        "priority": "medium",
        "acceptance_criteria": ["The behavior matches the published contract"],
        "updated_at": "2026-08-30T00:00:00Z",
        "estimated_hours": 1.5,
        "children": [],
        "metadata": {"source": "hardening-evaluation"},
    }


def write_specs(directory: Path, count: int, valid: bool) -> None:
    directory.mkdir()
    for index in range(count):
        payload = valid_spec()
        payload["name"] = f"Evaluation item {index}"
        if not valid:
            payload.pop("goal")
        (directory / f"item-{index:04d}.spec.json").write_text(json.dumps(payload) + "\n")


def evaluate(target: Path, case: str) -> tuple[bool, dict]:
    spec = target / "scripts" / "spec"
    temp_parent = target / "tests" / "tmp"
    temp_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hardening-eval-case-", dir=temp_parent) as temporary:
        workspace = Path(temporary)
        input_file = workspace / "input.spec.json"
        input_file.write_text(json.dumps(valid_spec(), indent=2) + "\n")

        if case == "version_contract":
            result = run(spec, ["version", "--json"], workspace)
            try:
                payload = json.loads(result.stdout)
            except json.JSONDecodeError:
                payload = {}
            passed = result.returncode == 0 and {"version", "contract", "schema_version"} <= payload.keys()

        elif case == "full_schema_validation":
            result = run(spec, ["validate", input_file.name, "--strict", "--json"], workspace)
            passed = result.returncode == 0

        elif case == "large_batch":
            directory = workspace / "valid-100"
            write_specs(directory, 100, valid=True)
            result = run(spec, ["validate-all", directory.name], workspace)
            passed = result.returncode == 0 and "100 passed, 0 failed" in result.stdout

        elif case == "failure_count_256":
            directory = workspace / "invalid-256"
            write_specs(directory, 256, valid=False)
            result = run(spec, ["validate-all", directory.name], workspace)
            passed = result.returncode != 0 and "0 passed, 256 failed" in result.stdout

        elif case == "runtime_failure":
            result = run(spec, ["render", input_file.name], workspace, env={"KUJO_BIN": "/bin/false"})
            passed = result.returncode != 0 and "Render failed" in result.stderr

        elif case == "agent_export":
            result = run(spec, ["export-agent-context", input_file.name], workspace)
            passed = (
                result.returncode == 0
                and "## Task: Hardening evaluation" in result.stdout
                and "### Acceptance Criteria" in result.stdout
                and len(result.stdout.encode()) < 16_384
            )

        elif case == "interactive_injection":
            output = workspace / "interactive.spec.yml"
            hostile_name = 'unsafe": injected: true #'
            answers = f"{hostile_name}\nA safe goal\nmedium\n\n{output.name}\n"
            result = run(spec, ["init-interactive"], workspace, stdin=answers)
            passed = result.returncode != 0 and not output.exists()

        elif case == "graph_escaping":
            graph_dir = workspace / "graph"
            graph_dir.mkdir()
            payload = valid_spec()
            payload["name"] = 'safe"]\n    injected["node'
            (graph_dir / "hostile.spec.json").write_text(json.dumps(payload) + "\n")
            result = run(spec, ["graph", str(graph_dir), "--format", "mermaid"], workspace)
            passed = result.returncode == 0 and '\\n    injected[\\"node' in result.stdout

        elif case == "requested_format":
            template_dir = workspace / "specs" / "templates"
            template_dir.mkdir(parents=True)
            template = template_dir / "evaluation.template.yml"
            template.write_text('name: "Template"\ngoal: "Preserve requested format"\n')
            output = workspace / "created.spec.json"
            result = run(
                spec,
                ["init", "--from", "template:evaluation", "--format", "json", "--output", output.name],
                workspace,
            )
            try:
                parsed = json.loads(output.read_text()) if output.exists() else None
            except json.JSONDecodeError:
                parsed = None
            passed = result.returncode == 0 and isinstance(parsed, dict)

        elif case == "cache_symlink":
            cache_root = workspace / "cache-root"
            cache_root.mkdir()
            trap = workspace / "trap"
            trap.mkdir()
            os.symlink(trap, cache_root / ".spec_cache")
            os.symlink(trap, cache_root / f"kujo-spec-cache-{os.getuid()}")
            yaml_file = workspace / "cache-input.spec.yml"
            yaml_file.write_text('name: "Cache test"\ngoal: "Do not follow cache symlinks"\n')
            result = run(spec, ["validate", yaml_file.name], workspace, env={"TMPDIR": str(cache_root)})
            passed = result.returncode == 0 and not any(trap.iterdir())

        elif case == "timeout_validation":
            result = run(spec, ["version", "--json"], workspace, env={"SPEC_TIMEOUT": "invalid"})
            passed = result.returncode != 0 and "positive integer" in result.stderr

        else:
            raise ValueError(f"Unknown case: {case}")

        details = {
            "case": case,
            "passed": passed,
            "exit_code": result.returncode,
            "stdout_bytes": len(result.stdout.encode()),
            "stderr_bytes": len(result.stderr.encode()),
            "stdout_preview": result.stdout[:400],
            "stderr_preview": result.stderr[:400],
        }
        return passed, details


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--case", required=True)
    args = parser.parse_args()
    passed, details = evaluate(args.target.resolve(), args.case)
    print(json.dumps(details, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
