#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
runtime_version="${1:-${KUJO_RUNTIME_VERSION:-}}"
install_dir="${2:-${KUJO_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/kujo-runtime/bin}}"
checksum_file="${KUJO_RUNTIME_CHECKSUM_FILE:-$repo_root/.github/kujo-runtime-checksums.txt}"

if [[ ! "$runtime_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "[kujo-runtime] ERROR: version must be an explicit semantic version" >&2
	exit 1
fi

os_name="$(uname -s)"
arch_name="$(uname -m)"
case "$os_name:$arch_name" in
	Linux:x86_64|Linux:amd64) platform="linux-x64" ;;
	Darwin:arm64|Darwin:aarch64) platform="macos-arm64" ;;
	Darwin:x86_64|Darwin:amd64) platform="macos-x64" ;;
	*)
		echo "[kujo-runtime] ERROR: unsupported runner platform: $os_name $arch_name" >&2
		exit 1
		;;
esac

archive_name="kujo-v${runtime_version}-${platform}.tar.gz"
expected_sha="$(awk -v archive="$archive_name" '$2 == archive { print $1 }' "$checksum_file" 2>/dev/null || true)"
if [[ ! "$expected_sha" =~ ^[0-9a-f]{64}$ ]]; then
	echo "[kujo-runtime] ERROR: no pinned checksum for $archive_name" >&2
	exit 1
fi

download_dir="$(mktemp -d -t kujo_runtime_XXXXXX)"
trap 'rm -rf "$download_dir"' EXIT
archive_path="$download_dir/$archive_name"
release_url="https://github.com/kujolang/kujo/releases/download/v${runtime_version}/${archive_name}"

echo "[kujo-runtime] downloading $archive_name"
curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
	--output "$archive_path" "$release_url"

if command -v sha256sum >/dev/null 2>&1; then
	actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
	actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
else
	echo "[kujo-runtime] ERROR: no SHA-256 tool found" >&2
	exit 1
fi

if [[ "$actual_sha" != "$expected_sha" ]]; then
	echo "[kujo-runtime] ERROR: checksum mismatch for $archive_name" >&2
	exit 1
fi

archive_entries="$(tar -tzf "$archive_path")"
if [[ "$archive_entries" != "kujo" && "$archive_entries" != "./kujo" ]]; then
	echo "[kujo-runtime] ERROR: release archive contains unexpected paths" >&2
	exit 1
fi

extract_dir="$download_dir/extract"
mkdir -p "$extract_dir" "$install_dir"
tar -xzf "$archive_path" -C "$extract_dir"
binary_path="$extract_dir/kujo"
[[ -f "$binary_path" ]] || binary_path="$extract_dir/./kujo"
install -m 0755 "$binary_path" "$install_dir/kujo"

installed_version="$("$install_dir/kujo" --version)"
if [[ "$installed_version" != "kujo $runtime_version" ]]; then
	echo "[kujo-runtime] ERROR: expected 'kujo $runtime_version', got '$installed_version'" >&2
	exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
	printf 'KUJO_BIN=%s\n' "$install_dir/kujo" >> "$GITHUB_ENV"
fi
if [[ -n "${GITHUB_PATH:-}" ]]; then
	printf '%s\n' "$install_dir" >> "$GITHUB_PATH"
fi

echo "[kujo-runtime] installed $installed_version at $install_dir/kujo"
