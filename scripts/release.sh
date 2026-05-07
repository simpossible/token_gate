#!/bin/bash
# Usage: ./scripts/release.sh v0.1.3
#
# Prerequisites:
#   - SSH key added to GitHub (for git push / homebrew-tap push)
#   - Run from the project root directory
#
# What this script does:
#   1. Tags the commit and pushes → GitHub Actions builds + creates Release automatically
#   2. Polls until the Release is ready (checksums.txt available, ~5-8 min)
#   3. Clones homebrew-tap, updates the formula with CI-built SHA256s, pushes

set -e

VERSION=${1:-}
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>  e.g. $0 v0.1.3"
  exit 1
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in format vX.Y.Z (e.g. v0.1.3)"
  exit 1
fi

VERSION_NUM=${VERSION#v}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKSUMS_URL="https://github.com/simpossible/token_gate/releases/download/${VERSION}/checksums.txt"

echo "==> Releasing $VERSION"

# ── 1. Tag and push ────────────────────────────────────────────────────────
echo "==> Tagging $VERSION and pushing..."
cd "$REPO_ROOT"
git tag "$VERSION"
git push origin "$VERSION"
git push origin master
echo "    GitHub Actions will now build and create the Release automatically."
echo "    Check progress at: https://github.com/simpossible/token_gate/actions"

# ── 2. Poll until GitHub Actions Release is ready ─────────────────────────
echo "==> Waiting for GitHub Actions to publish the Release (this takes ~5-8 min)..."
MAX_TRIES=30
for i in $(seq 1 $MAX_TRIES); do
  STATUS=$(curl -sI -o /dev/null -w "%{http_code}" -L "$CHECKSUMS_URL")
  if [ "$STATUS" = "200" ]; then
    echo "    Release is ready!"
    break
  fi
  if [ "$i" = "$MAX_TRIES" ]; then
    echo "Error: Timed out waiting for release. Check GitHub Actions for errors."
    exit 1
  fi
  echo "    [${i}/${MAX_TRIES}] Not ready yet (HTTP $STATUS), retrying in 30s..."
  sleep 30
done

# ── 3. Get SHA256s from CI-built checksums ─────────────────────────────────
echo "==> Fetching SHA256s from CI release..."
CHECKSUMS=$(curl -sL "$CHECKSUMS_URL")
ARM64_SHA=$(echo "$CHECKSUMS" | grep arm64 | awk '{print $1}')
AMD64_SHA=$(echo "$CHECKSUMS" | grep amd64 | awk '{print $1}')
echo "    arm64: $ARM64_SHA"
echo "    amd64: $AMD64_SHA"

# ── 4. Update homebrew-tap ─────────────────────────────────────────────────
echo "==> Updating homebrew-tap..."
TAP_DIR=$(mktemp -d)
git clone git@github.com:simpossible/homebrew-tap.git "$TAP_DIR"

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
echo "    Install:  brew tap simpossible/tap && brew install token_gate"
echo "    Upgrade:  brew upgrade token_gate"
