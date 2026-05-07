#!/bin/bash
# Usage: ./scripts/release.sh v0.1.2
#
# Prerequisites:
#   - gh CLI authenticated: gh auth login -h github.com
#   - SSH key added to GitHub (for git push)
#   - Run from the project root directory
#
# What this script does:
#   1. Cross-compiles for darwin/arm64 and darwin/amd64
#   2. Packages into .tar.gz files
#   3. Tags the commit and pushes to origin
#   4. Creates a GitHub Release and uploads tarballs
#   5. Clones homebrew-tap, updates the formula, pushes

set -e

VERSION=${1:-}
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>  e.g. $0 v0.1.2"
  exit 1
fi

# Validate version format
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in format vX.Y.Z (e.g. v0.1.2)"
  exit 1
fi

VERSION_NUM=${VERSION#v}  # Strip leading 'v' for formula
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_REPO="git@github.com:simpossible/homebrew-tap.git"

echo "==> Releasing $VERSION"

# ── 1. Build binaries ──────────────────────────────────────────────────────
echo "==> Building binaries..."
cd "$REPO_ROOT/server"
make release-binaries

ARM64_SHA=$(shasum -a 256 token_gate_darwin_arm64.tar.gz | awk '{print $1}')
AMD64_SHA=$(shasum -a 256 token_gate_darwin_amd64.tar.gz | awk '{print $1}')
echo "arm64 sha256: $ARM64_SHA"
echo "amd64 sha256: $AMD64_SHA"

# ── 2. Tag and push ────────────────────────────────────────────────────────
echo "==> Tagging $VERSION and pushing..."
cd "$REPO_ROOT"
git tag "$VERSION"
git push origin "$VERSION"
git push origin master

# ── 3. Create GitHub Release ───────────────────────────────────────────────
echo "==> Creating GitHub Release $VERSION..."
cd "$REPO_ROOT/server"
gh release create "$VERSION" \
  token_gate_darwin_arm64.tar.gz \
  token_gate_darwin_amd64.tar.gz \
  --title "$VERSION" \
  --notes "Release $VERSION"

# ── 4. Update homebrew-tap ─────────────────────────────────────────────────
echo "==> Updating homebrew-tap..."
TAP_DIR=$(mktemp -d)
git clone "$TAP_REPO" "$TAP_DIR"

cat > "$TAP_DIR/Formula/token_gate.rb" << EOF
class TokenGate < Formula
  desc "Local proxy gateway for managing multiple Claude API keys"
  homepage "https://github.com/simpossible/token_gate"
  version "$VERSION_NUM"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/simpossible/token_gate/releases/download/v#{version}/token_gate_darwin_arm64.tar.gz"
      sha256 "$ARM64_SHA"
    end
    on_intel do
      url "https://github.com/simpossible/token_gate/releases/download/v#{version}/token_gate_darwin_amd64.tar.gz"
      sha256 "$AMD64_SHA"
    end
  end

  def install
    on_arm do
      bin.install "token_gate_darwin_arm64" => "token_gate"
    end
    on_intel do
      bin.install "token_gate_darwin_amd64" => "token_gate"
    end
  end

  service do
    run [opt_bin/"token_gate", "server"]
    keep_alive true
  end

  def caveats
    <<~EOS
      Run Token Gate:
        token_gate start    # start in background and open browser
        token_gate stop     # stop the background process
        token_gate show     # open the web interface
        token_gate status   # check if running

      Or start automatically on login:
        brew services start token_gate

      Web interface: http://127.0.0.1:12123
      Logs: ~/.token_gate/logs/token_gate.log
    EOS
  end
end
EOF

cd "$TAP_DIR"
git add Formula/token_gate.rb
git commit -m "feat: update token_gate formula to $VERSION"
git push origin main

rm -rf "$TAP_DIR"

echo ""
echo "==> Done! $VERSION released."
echo "    Users can install with:"
echo "      brew tap simpossible/tap"
echo "      brew install token_gate"
