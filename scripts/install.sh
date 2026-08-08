#!/usr/bin/env bash
# Spec — one-command install script.
# Usage: curl -fsSL https://raw.githubusercontent.com/kujolang/spec/main/scripts/install.sh | bash
set -euo pipefail

SPEC_VERSION="${SPEC_VERSION:-1.0.0}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
REPO_URL="https://github.com/kujolang/spec"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SOURCE_DIR="${INSTALL_SOURCE_DIR:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Spec Installer v${SPEC_VERSION}"
echo ""

# Check for required dependencies
check_dep() {
	if ! command -v "$1" &>/dev/null; then
		echo -e "${RED}Error: '$1' is required but not installed.${NC}"
		echo "Install $1 and try again."
		exit 1
	fi
}

check_dep python3
check_dep git

# Determine install method: clone repo or download script only
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

echo "Cloning kujolang/spec..."
SOURCE_REPO=""

if [[ -n "$INSTALL_SOURCE_DIR" ]]; then
	if [[ ! -d "$INSTALL_SOURCE_DIR" ]]; then
		echo -e "${RED}INSTALL_SOURCE_DIR does not exist: $INSTALL_SOURCE_DIR${NC}"
		exit 1
	fi
	SOURCE_REPO="$INSTALL_SOURCE_DIR"
	echo "Using source from INSTALL_SOURCE_DIR: $SOURCE_REPO"
elif git clone --depth 1 "$REPO_URL" "$TMPDIR/repo" 2>/dev/null; then
	SOURCE_REPO="$TMPDIR/repo"
else
	# Local fallback for offline installs from an existing checkout
	local_repo="$(cd "$SCRIPT_DIR/.." && pwd)"
	if [[ -f "$local_repo/scripts/spec" ]]; then
		echo -e "${YELLOW}Clone failed; falling back to local checkout at $local_repo${NC}"
		SOURCE_REPO="$local_repo"
	else
		echo -e "${RED}Failed to clone $REPO_URL and no local checkout was found.${NC}"
		echo "Set INSTALL_SOURCE_DIR to a local kujo-spec checkout and retry."
		exit 1
	fi
fi

# Copy the spec script to install directory
if [[ -w "$INSTALL_DIR" ]]; then
	cp "$SOURCE_REPO/scripts/spec" "$INSTALL_DIR/spec"
	chmod +x "$INSTALL_DIR/spec"
else
	echo "Need sudo to install to $INSTALL_DIR"
	sudo cp "$SOURCE_REPO/scripts/spec" "$INSTALL_DIR/spec"
	sudo chmod +x "$INSTALL_DIR/spec"
fi

# Copy support scripts
SUPPORT_DIR="$HOME/.local/share/kujo-spec"
mkdir -p "$SUPPORT_DIR"
cp "$SOURCE_REPO/scripts/spec_yaml_to_json.py" "$SUPPORT_DIR/"
cp "$SOURCE_REPO/scripts/spec_toml_to_json.py" "$SUPPORT_DIR/"
cp -r "$SOURCE_REPO/src" "$SUPPORT_DIR/"
cp "$SOURCE_REPO/schema/spec.schema.json" "$SUPPORT_DIR/"

echo ""
echo -e "${GREEN}Spec installed to $INSTALL_DIR/spec${NC}"
echo ""

# Check for Kujo runtime
if [[ -n "${KUJO_BIN:-}" ]] && [[ -x "$KUJO_BIN" ]]; then
	echo -e "${GREEN}Kujo runtime found at $KUJO_BIN${NC}"
elif command -v kujo &>/dev/null; then
	echo -e "${YELLOW}Using 'kujo' from PATH. Set KUJO_BIN for a specific runtime path.${NC}"
else
	echo -e "${YELLOW}Warning: Kujo runtime not found on PATH.${NC}"
	echo "Set KUJO_BIN to the Kujo language runtime:"
	echo "  export KUJO_BIN=/path/to/kujo/target/release/kujo"
	echo ""
	echo "Or add it to your shell profile (~/.zshrc or ~/.bashrc):"
	echo "  echo 'export KUJO_BIN=/path/to/kujo/target/release/kujo' >> ~/.zshrc"
fi

echo ""
echo "Quick start:"
echo "  spec init --name 'my-first-spec'"
echo "  spec help"
echo ""
echo "Documentation: $REPO_URL"
echo "Support directory: $SUPPORT_DIR"
