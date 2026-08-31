#!/usr/bin/env python3
"""Run identical, interleaved Spec benchmarks against two repository states."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    import psutil
except ImportError:  # pragma: no cover - optional instrumentation
    psutil = None


def command_output(command: list[str]) -> str:
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return f"unavailable: {exc}"


def make_spec(index: int, valid: bool = True) -> dict:
    payload = {
        "name": f"Evaluation workload {index}",
        "goal": f"Validate deterministic workload item {index}",
        "version": "1.0.0",
        "status": "ready",
        "priority": "medium",
        "acceptance_criteria": ["Validation returns the documented result"],
        "tags": ["hardening-evaluation", f"item-{index}"],
    }
    if not valid:
        payload.pop("goal")
    return payload


def prepare_workspace(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for size in (1, 10, 50, 100, 256):
        directory = root / (f"valid-{size}" if size != 256 else "invalid-256")
        directory.mkdir()
        for index in range(size):
            valid = size != 256
            (directory / f"item-{index:04d}.spec.json").write_text(
                json.dumps(make_spec(index, valid=valid), sort_keys=True) + "\n"
            )

    complex_spec = make_spec(999)
    complex_spec.update(
        {
            "background": "A representative agent-facing task contract.",
            "scope": "Validation, rendering, export, and evidence preservation.",
            "non_goals": ["No network access", "No repository mutation"],
            "relevant_systems": ["kujo-spec", "kujo-eval"],
            "likely_files": ["scripts/spec", "src/validate.kujo"],
            "risks": [
                {
                    "risk": "A malformed contract could reach an agent.",
                    "severity": "high",
                    "mitigation": "Validate before export.",
                }
            ],
            "dependencies": ["Kujo runtime"],
            "human_approval_points": ["Before publishing evaluation results"],
        }
    )
    (root / "complex.spec.json").write_text(json.dumps(complex_spec, indent=2) + "\n")
    malformed = make_spec(1000)
    malformed["status"] = "not-a-real-status"
    malformed["acceptance_criteria"] = []
    (root / "schema-invalid.spec.json").write_text(json.dumps(malformed, indent=2) + "\n")


def parse_time_stats(path: Path) -> dict:
    text = path.read_text() if path.exists() else ""
    stats: dict[str, float | int | str | None] = {
        "user_seconds": None,
        "system_seconds": None,
        "max_rss_bytes": None,
        "page_reclaims": None,
        "page_faults": None,
        "block_inputs": None,
        "block_outputs": None,
        "raw": text,
    }
    patterns = {
        "user_seconds": r"^user\s+([0-9.]+)$",
        "system_seconds": r"^sys\s+([0-9.]+)$",
        "max_rss_bytes": r"^\s*(\d+)\s+maximum resident set size$",
        "page_reclaims": r"^\s*(\d+)\s+page reclaims$",
        "page_faults": r"^\s*(\d+)\s+page faults$",
        "block_inputs": r"^\s*(\d+)\s+block input operations$",
        "block_outputs": r"^\s*(\d+)\s+block output operations$",
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, text, re.MULTILINE)
        if match:
            stats[key] = float(match.group(1)) if "seconds" in key else int(match.group(1))
    return stats


def measured_run(command: list[str], cwd: Path, environment: dict[str, str]) -> dict:
    with tempfile.NamedTemporaryFile(prefix="spec-eval-time-", delete=False) as handle:
        time_path = Path(handle.name)
    wrapped = ["/usr/bin/time", "-lp", "-o", str(time_path), *command]
    started = time.perf_counter_ns()
    process = subprocess.Popen(
        wrapped,
        cwd=cwd,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    observed_pids = {process.pid}
    while process.poll() is None:
        if psutil is not None:
            try:
                observed_pids.update(child.pid for child in psutil.Process(process.pid).children(recursive=True))
            except (psutil.Error, ProcessLookupError):
                pass
        time.sleep(0.001)
    stdout, stderr = process.communicate()
    ended = time.perf_counter_ns()
    time_stats = parse_time_stats(time_path)
    time_path.unlink(missing_ok=True)
    return {
        "wall_seconds": (ended - started) / 1_000_000_000,
        "exit_code": process.returncode,
        "stdout_bytes": len(stdout),
        "stderr_bytes": len(stderr),
        "stdout_lines": len(stdout.splitlines()),
        "stderr_lines": len(stderr.splitlines()),
        "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
        "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
        "stdout_preview": stdout[:500].decode("utf-8", errors="replace"),
        "stderr_preview": stderr[:500].decode("utf-8", errors="replace"),
        "processes_observed": len(observed_pids),
        **time_stats,
    }


def workload_definitions(target: Path, workspace: Path, kujo_bin: str) -> dict[str, dict]:
    spec = str(target / "scripts" / "spec")
    common_env = {
        "KUJO_BIN": kujo_bin,
        "SPEC_TIMEOUT": "30",
        "LC_ALL": "C",
        "LANG": "C",
        "TMPDIR": str(workspace / "tmp"),
    }
    (workspace / "tmp").mkdir(exist_ok=True)
    return {
        "startup_version": {
            "category": "minimal",
            "command": [spec, "version", "--json"],
            "env": common_env,
        },
        "validate_single": {
            "category": "typical",
            "command": [spec, "validate", "complex.spec.json", "--json"],
            "env": common_env,
        },
        "agent_export": {
            "category": "agent-facing",
            "command": [spec, "export-agent-context", "complex.spec.json"],
            "env": common_env,
        },
        "render": {
            "category": "typical",
            "command": [spec, "render", "complex.spec.json"],
            "env": common_env,
        },
        "schema_failure": {
            "category": "failure",
            "command": [spec, "validate", "schema-invalid.spec.json", "--strict", "--json"],
            "env": common_env,
        },
        "runtime_failure": {
            "category": "failure",
            "command": [spec, "render", "complex.spec.json"],
            "env": {**common_env, "KUJO_BIN": "/bin/false"},
        },
        **{
            f"validate_all_{size}": {
                "category": "scaling" if size < 100 else "large",
                "command": [spec, "validate-all", f"valid-{size}"],
                "env": common_env,
                "input_count": size,
            }
            for size in (1, 10, 50, 100)
        },
    }


def summarize(samples: list[dict]) -> dict:
    values = [sample["wall_seconds"] for sample in samples]
    ordered = sorted(values)

    def percentile(p: float) -> float:
        if len(ordered) == 1:
            return ordered[0]
        position = (len(ordered) - 1) * p
        lower = int(position)
        upper = min(lower + 1, len(ordered) - 1)
        fraction = position - lower
        return ordered[lower] * (1 - fraction) + ordered[upper] * fraction

    numeric_optional = ("user_seconds", "system_seconds", "max_rss_bytes", "processes_observed")
    summary = {
        "n": len(values),
        "min_seconds": min(values),
        "max_seconds": max(values),
        "mean_seconds": statistics.fmean(values),
        "median_seconds": statistics.median(values),
        "stddev_seconds": statistics.stdev(values) if len(values) > 1 else 0.0,
        "p95_seconds": percentile(0.95),
        "p99_seconds": percentile(0.99),
        "exit_codes": sorted(set(sample["exit_code"] for sample in samples)),
        "stdout_bytes": sorted(set(sample["stdout_bytes"] for sample in samples)),
        "stderr_bytes": sorted(set(sample["stderr_bytes"] for sample in samples)),
        "stdout_sha256": sorted(set(sample["stdout_sha256"] for sample in samples)),
    }
    for key in numeric_optional:
        present = [sample[key] for sample in samples if sample.get(key) is not None]
        if present:
            summary[f"median_{key}"] = statistics.median(present)
            summary[f"max_{key}"] = max(present)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--startup-runs", type=int, default=20)
    parser.add_argument("--kujo-bin", default=shutil.which("kujo") or "kujo")
    args = parser.parse_args()

    for target in (args.baseline, args.current):
        if not (target / "scripts" / "spec").is_file():
            parser.error(f"Not a Spec checkout: {target}")

    targets = {"baseline": args.baseline.resolve(), "current": args.current.resolve()}
    temporary_directories = []
    try:
        workspaces = {}
        for label, target in targets.items():
            temp_parent = target / "tests" / "tmp"
            temp_parent.mkdir(parents=True, exist_ok=True)
            temporary_directory = tempfile.TemporaryDirectory(
                prefix="hardening-eval-", dir=temp_parent
            )
            temporary_directories.append(temporary_directory)
            workspace = Path(temporary_directory.name)
            prepare_workspace(workspace)
            workspaces[label] = workspace
        definitions = {
            label: workload_definitions(target, workspaces[label], args.kujo_bin)
            for label, target in targets.items()
        }
        raw_samples: list[dict] = []
        workload_names = list(definitions["baseline"])

        for workload_name in workload_names:
            for warmup_index in range(args.warmups):
                order = ("baseline", "current") if warmup_index % 2 == 0 else ("current", "baseline")
                for label in order:
                    definition = definitions[label][workload_name]
                    environment = os.environ.copy()
                    environment.update(definition["env"])
                    measured_run(definition["command"], workspaces[label], environment)

            run_count = args.startup_runs if workload_name == "startup_version" else args.runs
            for run_index in range(run_count):
                order = ("baseline", "current") if run_index % 2 == 0 else ("current", "baseline")
                for label in order:
                    definition = definitions[label][workload_name]
                    environment = os.environ.copy()
                    environment.update(definition["env"])
                    sample = measured_run(definition["command"], workspaces[label], environment)
                    sample.update(
                        {
                            "target": label,
                            "target_sha": command_output(["git", "-C", str(targets[label]), "rev-parse", "HEAD"]),
                            "workload": workload_name,
                            "category": definition["category"],
                            "run_index": run_index,
                            "order_in_pair": order.index(label),
                            "input_count": definition.get("input_count"),
                        }
                    )
                    raw_samples.append(sample)

        summaries: dict[str, dict] = {}
        for workload_name in workload_names:
            summaries[workload_name] = {}
            for label in targets:
                selected = [
                    sample
                    for sample in raw_samples
                    if sample["workload"] == workload_name and sample["target"] == label
                ]
                summaries[workload_name][label] = summarize(selected)

        result = {
            "schema_version": "1.0.0",
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "method": {
                "warmups_per_target": args.warmups,
                "measured_runs_default": args.runs,
                "measured_runs_startup": args.startup_runs,
                "pairing": "baseline/current order alternated within each measured pair",
                "timer": "Python perf_counter_ns around /usr/bin/time -lp",
                "rss": "maximum resident set size reported by macOS /usr/bin/time -l",
                "process_count": "1 ms psutil sampling; lower bound for very short-lived processes",
            },
            "environment": {
                "platform": platform.platform(),
                "machine": platform.machine(),
                "python": sys.version,
                "kujo": command_output([args.kujo_bin, "--version"]),
                "git": command_output(["git", "--version"]),
                "cpu": command_output(["sysctl", "-n", "machdep.cpu.brand_string"]),
                "physical_cores": command_output(["sysctl", "-n", "hw.physicalcpu"]),
                "logical_cores": command_output(["sysctl", "-n", "hw.logicalcpu"]),
                "memory_bytes": command_output(["sysctl", "-n", "hw.memsize"]),
                "psutil": getattr(psutil, "__version__", None),
            },
            "targets": {
                label: {
                    "path": str(path),
                    "sha": command_output(["git", "-C", str(path), "rev-parse", "HEAD"]),
                }
                for label, path in targets.items()
            },
            "workloads": {
                name: {
                    key: value
                    for key, value in definitions["current"][name].items()
                    if key not in {"env"}
                }
                for name in workload_names
            },
            "summaries": summaries,
            "samples": raw_samples,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    finally:
        for temporary_directory in temporary_directories:
            temporary_directory.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
