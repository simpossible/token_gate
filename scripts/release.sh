#!/bin/bash
# Usage: ./scripts/release.sh v0.2.1
#
# Prerequisites:
#   - SSH key added to GitHub (for git push / homebrew-tap push)
#   - GitHub Personal Access Token (for creating release + uploading DMG):
#     export TOKEN_GATE_GITHUB_TOKEN="ghp_xxxx"
#   - Apple notarization credentials in env vars (for build_dmg.sh)
#   - Run from the project root directory
#
# What this script does:
#   1. Builds DMG locally (build_dmg.sh: Go + Flutter + sign + notarize)
#   2. Tags the commit and pushes to GitHub
#   3. Creates a GitHub Release via API and uploads the DMG
#   4. Clones homebrew-tap, updates the Cask with new version + SHA256, pushes

set -e

VERSION=${1:-}
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>  e.g. $0 v0.2.1"
  exit 1
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in format vX.Y.Z (e.g. v0.2.1)"
  exit 1
fi

VERSION_NUM=${VERSION#v}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG_NAME="TokenGate-${VERSION_NUM}.dmg"
DMG_PATH="$REPO_ROOT/build/$DMG_NAME"
REPO_API="https://api.github.com/repos/simpossible/token_gate"
UPLOAD_API="https://uploads.github.com/repos/simpossible/token_gate"

if [ -z "${TOKEN_GATE_GITHUB_TOKEN:-}" ]; then
  echo "Error: TOKEN_GATE_GITHUB_TOKEN not set."
  echo "  Create a PAT at: https://github.com/settings/tokens (needs repo scope)"
  echo "  export TOKEN_GATE_GITHUB_TOKEN='ghp_xxxx'"
  exit 1
fi

echo "==> Releasing $VERSION"

# ── 1. Build DMG locally ─────────────────────────────────────────────────
echo "==> Building DMG..."
cd "$REPO_ROOT"
./scripts/build_dmg.sh "$VERSION_NUM"

if [ ! -f "$DMG_PATH" ]; then
  echo "Error: DMG not found at $DMG_PATH"
  exit 1
fi

DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "    DMG: $DMG_PATH"
echo "    SHA256: $DMG_SHA256"

# ── 2. Tag and push ──────────────────────────────────────────────────────
echo "==> Tagging $VERSION and pushing..."
cd "$REPO_ROOT"
git tag "$VERSION"
git push origin "$VERSION"
git push origin master

# ── 3. Create GitHub Release and upload DMG ──────────────────────────────
echo "==> Creating GitHub Release..."
RESPONSE=$(curl -s -X POST \
  -H "Authorization: token $TOKEN_GATE_GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"$VERSION\",
    \"name\": \"$VERSION\",
    \"body\": \"Token Gate $VERSION\\n\\nDownload TokenGate-${VERSION_NUM}.dmg, drag to Applications.\\n\\nFirst open: right-click → Open → confirm.\",
    \"draft\": false,
    \"prerelease\": false
  }" \
  "$REPO_API/releases")

RELEASE_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)

if [ -z "$RELEASE_ID" ]; then
  echo "Error: Failed to create release."
  echo "$RESPONSE"
  exit 1
fi

echo "    Release created (ID: $RELEASE_ID)"

echo "==> Uploading DMG..."
curl -s -X POST \
  -H "Authorization: token $TOKEN_GATE_GITHUB_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$DMG_PATH" \
  "$UPLOAD_API/releases/$RELEASE_ID/assets?name=$DMG_NAME" > /dev/null

echo "    DMG uploaded"

# ── 4. Update homebrew-tap (Cask) ───────────────────────────────────────
echo "==> Updating homebrew-tap..."
TAP_DIR=$(mktemp -d)
git clone git@github.com:simpossible/homebrew-tap.git "$TAP_DIR"

mkdir -p "$TAP_DIR/Casks"

cat > "$TAP_DIR/Casks/token-gate.rb" << EOF
cask "token-gate" do
  version "${VERSION_NUM}"
  sha256 "${DMG_SHA256}"

  url "https://github.com/simpossible/token_gate/releases/download/v#{version}/TokenGate-#{version}.dmg"
  name "Token Gate"
  desc "Local proxy gateway for managing multiple Claude API keys"
  homepage "https://github.com/simpossible/token_gate"

  depends_on macos: ">= :catalina"

  app "TokenGate.app"
end
EOF

cd "$TAP_DIR"
git add Casks/token-gate.rb
git commit -m "feat: update token-gate cask to ${VERSION}"
git push origin main

rm -rf "$TAP_DIR"

echo ""
echo "==> Done! ${VERSION} released."
echo "    DMG:   https://github.com/simpossible/token_gate/releases/download/${VERSION}/${DMG_NAME}"
echo "    Install:  brew tap simpossible/tap && brew install --cask token-gate"
echo "    Upgrade:  brew upgrade --cask token-gate"
