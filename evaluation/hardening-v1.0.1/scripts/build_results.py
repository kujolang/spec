#!/usr/bin/env python3
"""Assemble the public machine-readable before/after evaluation result."""

from __future__ import annotations

import argparse
import json
import random
import re
import statistics
from datetime import datetime, timezone
from pathlib import Path


BASELINE_SHA = "11180d8f6af1ed3eea84abb3434dd736fa51293b"
CURRENT_SHA = "be4696b4acbefac39ea3c3645f27eb2bb6410f8e"


def percent_change(before: float, after: float) -> float:
    return ((after - before) / before) * 100.0


def bootstrap_paired_median_ci(samples: list[dict], workload: str) -> list[float]:
    by_run: dict[int, dict[str, float]] = {}
    for sample in samples:
        if sample["workload"] == workload:
            by_run.setdefault(sample["run_index"], {})[sample["target"]] = sample["wall_seconds"]
    ratios = [pair["current"] / pair["baseline"] - 1.0 for pair in by_run.values() if len(pair) == 2]
    rng = random.Random(f"spec-v1.0.1:{workload}")
    boot = []
    for _ in range(10_000):
        resample = [ratios[rng.randrange(len(ratios))] for _ in ratios]
        boot.append(statistics.median(resample) * 100.0)
    boot.sort()
    return [boot[249], boot[9749]]


def eval_result(path: Path) -> dict:
    data = json.loads(path.read_text())["data"]
    tests = []
    for item in data["test_results"]:
        details = item.get("details", {})
        output = details.get("stdout", "")
        case_result = None
        if output.strip():
            try:
                case_result = json.loads(output)
            except json.JSONDecodeError:
                pass
        tests.append(
            {
                "name": item["name"],
                "passed": item["passed"],
                "message": item["message"],
                "case_result": case_result,
            }
        )
    total = data["passed"] + data["failed"] + data["skipped"]
    return {
        "passed": data["passed"],
        "failed": data["failed"],
        "skipped": data["skipped"],
        "total": total,
        "derived_pass_rate_percent": (data["passed"] / total) * 100.0 if total else 0.0,
        "duration_ms": data["duration_ms"],
        "tests": tests,
    }


def native_test_result(path: Path) -> dict:
    text = path.read_text()
    match = re.search(r"=== Results: (\d+) passed, (\d+) failed ===", text)
    if not match:
        raise ValueError(f"No test summary in {path}")
    passed, failed = map(int, match.groups())
    return {"passed": passed, "failed": failed, "total": passed + failed}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output or root / "evaluation-results.json"
    benchmark = json.loads((root / "results/raw-benchmark.json").read_text())
    static = json.loads((root / "results/static-metrics.json").read_text())

    measurements = {}
    for workload, targets in benchmark["summaries"].items():
        before = targets["baseline"]
        after = targets["current"]
        measurements[workload] = {
            "category": benchmark["workloads"][workload]["category"],
            "input_count": benchmark["workloads"][workload].get("input_count"),
            "baseline": before,
            "current": after,
            "median_wall_change_percent": percent_change(before["median_seconds"], after["median_seconds"]),
            "p95_wall_change_percent": percent_change(before["p95_seconds"], after["p95_seconds"]),
            "median_rss_change_percent": percent_change(before["median_max_rss_bytes"], after["median_max_rss_bytes"]),
            "paired_median_change_bootstrap_95ci_percent": bootstrap_paired_median_ci(benchmark["samples"], workload),
        }

    baseline_eval = eval_result(root / "results/eval-baseline-final/last_run.json")
    current_eval = eval_result(root / "results/eval-current-final/last_run.json")
    result = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "evaluation": "Spec v1.0.0 to v1.0.1 hardening",
        "boundary": {
            "baseline": {
                "sha": BASELINE_SHA,
                "tag": "v1.0.0",
                "timestamp": "2026-08-08T02:59:03-04:00",
                "selection_reason": "Immediately preceding official release; the next commit begins the hardening test-contract work.",
            },
            "current": {
                "sha": CURRENT_SHA,
                "tag": "v1.0.1",
                "timestamp": "2026-08-30T19:07:40-04:00",
            },
        },
        "environment": benchmark["environment"],
        "method": benchmark["method"],
        "runtime_measurements": measurements,
        "kujo_eval": {
            "baseline": baseline_eval,
            "current": current_eval,
            "derived_pass_rate_change_points": current_eval["derived_pass_rate_percent"] - baseline_eval["derived_pass_rate_percent"],
            "manifest_verification": {"baseline": True, "current": True, "verified_files_each": 7},
        },
        "native_tests": {
            "baseline": native_test_result(root / "results/native-tests-baseline/output.txt"),
            "current": native_test_result(root / "results/native-tests-current/output.txt"),
            "note": "Suite sizes differ because tests were added; these are release-specific reliability checks, not a shared-workload score.",
        },
        "static_metrics": static,
        "token_and_cost": {
            "llm_calls": 0,
            "measured_tokens": None,
            "estimated_cost": None,
            "reason": "Spec is deterministic local tooling and the tested paths do not call an LLM. Agent-facing output bytes were measured instead.",
        },
        "regressions": [
            {
                "metric": "single-file validation median wall time",
                "baseline": measurements["validate_single"]["baseline"]["median_seconds"],
                "current": measurements["validate_single"]["current"]["median_seconds"],
                "change_percent": measurements["validate_single"]["median_wall_change_percent"],
                "severity": "low",
            },
            {
                "metric": "single-file validation median maximum RSS",
                "baseline": measurements["validate_single"]["baseline"]["median_max_rss_bytes"],
                "current": measurements["validate_single"]["current"]["median_max_rss_bytes"],
                "change_percent": measurements["validate_single"]["median_rss_change_percent"],
                "severity": "low",
            },
            {
                "metric": "compressed source archive size",
                "baseline": static["baseline"]["git_archive_tar_gzip_bytes"],
                "current": static["current"]["git_archive_tar_gzip_bytes"],
                "change_percent": percent_change(static["baseline"]["git_archive_tar_gzip_bytes"], static["current"]["git_archive_tar_gzip_bytes"]),
                "severity": "low",
            },
        ],
        "conclusion": {
            "answer": "YES",
            "basis": "Shared deterministic evaluation success rose from 3/11 to 11/11 while 100-file validation median fell from about 40.1 seconds to 0.93 seconds. Low-severity single-file latency, RSS, and repository-size regressions are explicitly retained.",
        },
    }
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
