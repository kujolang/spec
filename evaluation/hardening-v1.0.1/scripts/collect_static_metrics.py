#!/usr/bin/env python3
"""Collect reproducible Git and codebase metrics for two repository revisions."""

from __future__ import annotations

import argparse
import gzip
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


SOURCE_SUFFIXES = {".sh", ".py", ".kujo"}
TEXT_SUFFIXES = SOURCE_SUFFIXES | {".md", ".yml", ".yaml", ".toml", ".json", ".rb"}
FUNCTION_RE = re.compile(r"^\s*(?:def\s+|function\s+|[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{)")
BRANCH_RE = re.compile(r"\b(?:if|elif|for|while|case|catch|except)\b|&&|\|\|")
TODO_RE = re.compile(r"\b(?:TODO|FIXME)\b")


def git(repo: Path, *args: str, binary: bool = False):
    completed = subprocess.run(
        ["git", *args], cwd=repo, check=True, capture_output=True
    )
    return completed.stdout if binary else completed.stdout.decode("utf-8", "replace")


def files_at(repo: Path, revision: str) -> list[str]:
    return [line for line in git(repo, "ls-tree", "-r", "--name-only", revision).splitlines() if line]


def blob(repo: Path, revision: str, path: str) -> str:
    return git(repo, "show", f"{revision}:{path}")


def classify(path: str) -> str:
    if path.startswith("tests/") or "/tests/" in path:
        return "test"
    if path.startswith("docs/") or path.endswith(".md"):
        return "documentation"
    if Path(path).suffix in SOURCE_SUFFIXES or path == "scripts/spec":
        return "source"
    return "other"


def revision_metrics(repo: Path, revision: str) -> dict:
    paths = files_at(repo, revision)
    metrics = {
        "tracked_files": len(paths),
        "files_by_category": dict(Counter(classify(path) for path in paths)),
        "text_files": 0,
        "total_lines": 0,
        "nonblank_lines": 0,
        "source_files": 0,
        "source_lines": 0,
        "test_lines": 0,
        "documentation_lines": 0,
        "function_definitions": 0,
        "branch_tokens": 0,
        "todo_fixme": 0,
        "largest_text_files": [],
    }
    sizes = []
    for path in paths:
        suffix = Path(path).suffix
        if suffix not in TEXT_SUFFIXES and path != "scripts/spec":
            continue
        try:
            text = blob(repo, revision, path)
        except subprocess.CalledProcessError:
            continue
        lines = text.splitlines()
        count = len(lines)
        category = classify(path)
        metrics["text_files"] += 1
        metrics["total_lines"] += count
        metrics["nonblank_lines"] += sum(bool(line.strip()) for line in lines)
        metrics["todo_fixme"] += len(TODO_RE.findall(text))
        sizes.append({"path": path, "lines": count})
        if category == "source":
            metrics["source_files"] += 1
            metrics["source_lines"] += count
            metrics["function_definitions"] += sum(bool(FUNCTION_RE.search(line)) for line in lines)
            metrics["branch_tokens"] += sum(len(BRANCH_RE.findall(line)) for line in lines)
        elif category == "test":
            metrics["test_lines"] += count
        elif category == "documentation":
            metrics["documentation_lines"] += count
    metrics["largest_text_files"] = sorted(sizes, key=lambda item: item["lines"], reverse=True)[:10]

    archive = git(repo, "archive", "--format=tar", revision, binary=True)
    metrics["git_archive_tar_bytes"] = len(archive)
    metrics["git_archive_tar_gzip_bytes"] = len(gzip.compress(archive, compresslevel=9, mtime=0))

    package = json.loads(blob(repo, revision, "package.json"))
    metrics["direct_dependencies"] = len(package.get("dependencies", {})) + len(package.get("devDependencies", {}))
    metrics["package_version"] = package.get("version")
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--current", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()

    commits = []
    fields = ["%H", "%h", "%aI", "%s"]
    raw = git(repo, "log", "--reverse", f"--format={'%x1f'.join(fields)}", f"{args.baseline}..{args.current}")
    for line in raw.splitlines():
        full, short, timestamp, subject = line.split("\x1f", 3)
        commits.append({"sha": full, "short_sha": short, "timestamp": timestamp, "subject": subject})

    numstat = git(repo, "diff", "--numstat", args.baseline, args.current)
    additions = deletions = binary_files = 0
    for line in numstat.splitlines():
        added, deleted, _ = line.split("\t", 2)
        if added == "-" or deleted == "-":
            binary_files += 1
        else:
            additions += int(added)
            deletions += int(deleted)

    result = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "baseline": {"revision": args.baseline, **revision_metrics(repo, args.baseline)},
        "current": {"revision": args.current, **revision_metrics(repo, args.current)},
        "diff": {
            "commit_count": len(commits),
            "changed_files": len(git(repo, "diff", "--name-only", args.baseline, args.current).splitlines()),
            "additions": additions,
            "deletions": deletions,
            "binary_files": binary_files,
            "commits": commits,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
