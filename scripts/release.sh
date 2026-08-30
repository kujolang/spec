#!/usr/bin/env bash
# Spec Release Script — runs quality gates, tags, and pushes a release.
# Usage: bash scripts/release.sh <version> [--dry-run]
set -euo pipefail

VERSION="${1:-}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=true; shift ;;
		*) VERSION="$1"; shift ;;
	esac
done

if [[ -z "$VERSION" ]]; then
	echo "Usage: bash scripts/release.sh <version> [--dry-run]"
	echo "Example: bash scripts/release.sh 0.2.0"
	exit 1
fi

# Validate version format (semver)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Error: Version must be semver (e.g., 0.2.0)"
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
	echo "Error: Tag v$VERSION already exists."
	exit 1
fi

echo "=== Spec Release v$VERSION ==="
echo ""

build_release_artifacts() {
	local release_version="$1"
	local out_dir="$2"
	local archive_base="kujo-spec-v${release_version}"
	local archive_file="$out_dir/${archive_base}.tar.gz"
	local checksum_file="$out_dir/${archive_base}.sha256"
	local provenance_file="$out_dir/${archive_base}.provenance.json"
	local commit_sha generated_at sha256

	mkdir -p "$out_dir"
	git archive --format=tar.gz --prefix="kujo-spec-${release_version}/" HEAD > "$archive_file"
	sha256="$(shasum -a 256 "$archive_file" | awk '{print $1}')"
	echo "$sha256  $(basename "$archive_file")" > "$checksum_file"

	commit_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
	generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

	python3 -c '
import json, sys
payload = {
	"version": sys.argv[1],
	"tag": "v" + sys.argv[1],
	"commit": sys.argv[2],
	"archive": sys.argv[3],
	"sha256": sys.argv[4],
	"generated_at": sys.argv[5],
	"generator": "scripts/release.sh"
}
with open(sys.argv[6], "w") as fh:
	json.dump(payload, fh, indent=2)
	fh.write("\n")
' "$release_version" "$commit_sha" "$(basename "$archive_file")" "$sha256" "$generated_at" "$provenance_file"

	echo "  Archive:    $archive_file"
	echo "  Checksum:   $checksum_file"
	echo "  Provenance: $provenance_file"
}

update_release_metadata() {
	local release_version="$1"
	local release_date
	release_date="$(date -u +"%Y-%m-%d")"

	python3 - "$release_version" "$release_date" <<'PY'
import json
import pathlib
import re
import sys

version, release_date = sys.argv[1:]

def replace_once(path, pattern, replacement):
    file_path = pathlib.Path(path)
    text = file_path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected one version marker in {path}, found {count}")
    file_path.write_text(updated)

pathlib.Path("VERSION").write_text(version + "\n")
pathlib.Path("RUNTIME_VERSION").write_text(version + "\n")
replace_once("scripts/spec", r'^VERSION="[^"]+"$', f'VERSION="{version}"')
replace_once(
    "scripts/install.sh",
    r'^SPEC_VERSION="\$\{SPEC_VERSION:-[^}]+\}"$',
    f'SPEC_VERSION="${{SPEC_VERSION:-{version}}}"',
)
replace_once("kennel.toml", r'^version = "[^"]+"$', f'version = "{version}"')
replace_once("kujo.toml", r'^version = "[^"]+"$', f'version = "{version}"')
replace_once("homebrew/spec.rb", r'^  version "[^"]+"$', f'  version "{version}"')
replace_once(
    "README.md",
    r'badge/version-[^-]+-black',
    f'badge/version-{version}-black',
)

package_path = pathlib.Path("package.json")
package = json.loads(package_path.read_text())
package["version"] = version
package_path.write_text(json.dumps(package, indent=2) + "\n")

changelog_path = pathlib.Path("CHANGELOG.md")
changelog = changelog_path.read_text()
release_heading = f"## [{version}] - {release_date}"
if release_heading not in changelog:
    marker = "## [Unreleased]"
    if changelog.count(marker) != 1:
        raise SystemExit("Expected exactly one Unreleased changelog heading")
    changelog = changelog.replace(marker, marker + "\n\n" + release_heading, 1)
    changelog_path.write_text(changelog)
PY
}

# Ensure clean working tree
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
	echo "Error: Working tree is not clean. Commit or stash changes first."
	git status --short
	exit 1
fi

# Ensure we're on main branch
BRANCH="$(git branch --show-current 2>/dev/null)" || BRANCH="unknown"
if [[ "$BRANCH" != "main" ]]; then
	echo "Warning: Not on main branch (current: $BRANCH)."
	echo "Continue? [y/N]"
	read -r answer
	[[ "$answer" =~ ^[Yy]$ ]] || exit 1
fi

# Step 1: Run tests
echo "1/6 Running test suite..."
if ! bash tests/run_tests.sh; then
	echo "Error: Tests failed. Fix before releasing."
	exit 1
fi
echo ""

# Step 2: Run release quality gates
echo "2/6 Running release quality gates..."
if [[ -f scripts/release_quality_gates.sh ]]; then
	if ! bash scripts/release_quality_gates.sh; then
		echo "Error: Quality gates failed."
		exit 1
	fi
else
	echo "  (no quality gates script — skipping)"
fi
echo ""

# Step 3: Update release metadata
echo "3/6 Updating release metadata to $VERSION..."
if [[ "$DRY_RUN" == "true" ]]; then
	echo "  [DRY RUN] Would update release metadata and changelog"
else
	update_release_metadata "$VERSION"
fi
echo ""

# Step 4: Commit version bump
echo "4/6 Committing version bump..."
if [[ "$DRY_RUN" == "true" ]]; then
	echo "  [DRY RUN] Would commit version bump"
else
	git add CHANGELOG.md README.md VERSION RUNTIME_VERSION homebrew/spec.rb \
		kennel.toml kujo.toml package.json scripts/install.sh scripts/spec
	if git diff --cached --quiet; then
		echo "  Release metadata already matches v$VERSION"
	else
		git commit -m "chore: prepare v$VERSION release"
	fi
fi
echo ""

# Step 5: Build release artifacts and provenance
echo "5/6 Building release artifacts..."
if [[ "$DRY_RUN" == "true" ]]; then
	DRY_DIST="$(mktemp -d -t kujo_spec_release_artifacts_XXXXXX)"
	echo "  [DRY RUN] Generating artifacts in: $DRY_DIST"
	build_release_artifacts "$VERSION" "$DRY_DIST"
	rm -rf "$DRY_DIST" 2>/dev/null || true
else
	build_release_artifacts "$VERSION" "$PROJECT_DIR/dist"
fi
echo ""

# Step 6: Tag and push
echo "6/6 Tagging and pushing..."
if [[ "$DRY_RUN" == "true" ]]; then
	echo "  [DRY RUN] Would: git tag v$VERSION && git push && git push --tags"
else
	git tag -a "v$VERSION" -m "Spec v$VERSION"
	git push origin main
	git push origin "v$VERSION"
fi

echo ""
echo "=== Release v$VERSION complete ==="
echo ""
echo "Next steps:"
echo "  1. Create GitHub Release: https://github.com/kujolang/spec/releases/new?tag=v$VERSION"
echo "  2. Draft release notes from docs/RELEASE_NOTES_TEMPLATE.md"
echo "  3. Attach dist/kujo-spec-v$VERSION.tar.gz + .sha256 + .provenance.json to release"
echo "  4. Update Homebrew formula if applicable"
echo "  5. Announce in relevant channels"
