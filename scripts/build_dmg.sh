#!/bin/bash
set -euo pipefail

# ============================================================
# Token Gate macOS DMG Build Script
#
# Prerequisites:
#   1. Developer ID Application certificate installed in Keychain
#   2. Apple app-specific password for notarization:
#      https://appleid.apple.com > Sign-In and Security > App-Specific Passwords
#   3. Set environment variables before running:
#      export TOKEN_GATE_APPLE_ID="your-apple-id@email.com"
#      export TOKEN_GATE_APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # app-specific password
#      export TOKEN_GATE_APPLE_TEAM_ID="5X939PFV35"
#
# Usage:
#   ./scripts/build_dmg.sh [version]
#
#   version  - optional, e.g. "2.0.0". Defaults to MARKETING_VERSION in pbxproj.
#
# Output:
#   build/TokenGate-{version}.dmg  (signed + notarized)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
SERVER_DIR="$PROJECT_ROOT/server"
BUILD_DIR="$PROJECT_ROOT/build"
PBXPROJ="$APP_DIR/macos/Runner.xcodeproj/project.pbxproj"
ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
SIGNING_IDENTITY="Developer ID Application: jinfeng liang (5X939PFV35)"

# Colors (all to stderr)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Check prerequisites ---
check_prereqs() {
    info "Checking prerequisites..."

    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        error "Developer ID Application certificate not found in Keychain."
    fi

    if [ -z "${TOKEN_GATE_APPLE_ID:-}" ] || [ -z "${TOKEN_GATE_APPLE_PASSWORD:-}" ] || [ -z "${TOKEN_GATE_APPLE_TEAM_ID:-}" ]; then
        error "Notarization credentials not set. Export these environment variables:
  export TOKEN_GATE_APPLE_ID='your-apple-id@email.com'
  export TOKEN_GATE_APPLE_PASSWORD='xxxx-xxxx-xxxx-xxxx'
  export TOKEN_GATE_APPLE_TEAM_ID='5X939PFV35'"
    fi

    if ! command -v flutter &>/dev/null; then
        error "flutter not found in PATH"
    fi

    info "Prerequisites OK"
}

# --- Get version ---
get_version() {
    if [ -n "${1:-}" ]; then
        echo "$1"
    else
        grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | head -1 | awk '{print $2}'
    fi
}

# --- Step 1: Build Go binary ---
build_go_binary() {
    info "Building Go binary..."
    cd "$SERVER_DIR"
    make build
    cp token_gate "$APP_DIR/assets/bin/token_gate"
    chmod +x "$APP_DIR/assets/bin/token_gate"
    info "Go binary built"
}

# --- Step 2: Flutter build with ad-hoc signing ---
build_flutter_app() {
    info "Building Flutter macOS app (Release)..."

    # Temporarily switch to ad-hoc signing for reliable builds
    sed -i '' 's/"CODE_SIGN_IDENTITY\[sdk=macosx\*\]" = "Developer ID Application"/"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-"/' "$PBXPROJ"

    cd "$APP_DIR"
    flutter build macos --release

    # Restore Developer ID in pbxproj
    sed -i '' 's/"CODE_SIGN_IDENTITY\[sdk=macosx\*\]" = "-"/"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Developer ID Application"/' "$PBXPROJ"

    info "Flutter build complete"
}

# --- Step 3: Sign with Developer ID (inside-out: Go binaries → frameworks → main bundle) ---
sign_app() {
    local app_path="$APP_DIR/build/macos/Build/Products/Release/app.app"
    info "Signing .app bundle with Developer ID + hardened runtime..."

    # 1) Sign embedded Go binaries (not covered by --deep)
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        "$app_path/Contents/Resources/token_gate"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        "$app_path/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/assets/bin/token_gate"

    # 2) Sign App.framework (contains the Go binary above)
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        "$app_path/Contents/Frameworks/App.framework"

    # 3) Sign remaining frameworks + main bundle
    codesign --force --deep \
             --sign "$SIGNING_IDENTITY" \
             --options runtime \
             --timestamp \
             --entitlements "$ENTITLEMENTS" \
             "$app_path"

    info "Signing complete"
}

# --- Step 4: Verify code signature ---
verify_signature() {
    local app_path="$APP_DIR/build/macos/Build/Products/Release/app.app"
    info "Verifying code signature..."
    codesign --verify --deep --strict "$app_path" 2>&1 || {
        error "Code signature verification failed!"
    }
    codesign -dvv "$app_path" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime"
    info "Code signature valid"
}

# --- Step 5: Create DMG using hdiutil ---
create_dmg() {
    local version="$1"
    local app_path="$APP_DIR/build/macos/Build/Products/Release/app.app"
    local dmg_name="TokenGate-${version}.dmg"
    local dmg_path="$BUILD_DIR/$dmg_name"
    local staging="$BUILD_DIR/dmg_staging"

    mkdir -p "$BUILD_DIR"
    rm -f "$dmg_path"
    rm -rf "$staging"

    info "Creating DMG: $dmg_name..."

    mkdir -p "$staging"
    cp -R "$app_path" "$staging/"
    ln -sf /Applications "$staging/Applications"

    hdiutil create -volname "TokenGate" \
        -srcfolder "$staging" \
        -ov -format UDZO \
        "$dmg_path" >&2

    rm -rf "$staging"
    info "DMG created: $dmg_path"
    echo "$dmg_path"
}

# --- Step 6: Sign DMG ---
sign_dmg() {
    local dmg_path="$1"
    info "Signing DMG..."
    codesign --sign "$SIGNING_IDENTITY" \
             --timestamp \
             "$dmg_path"
    info "DMG signed"
}

# --- Step 7: Notarize DMG ---
notarize_dmg() {
    local dmg_path="$1"
    info "Submitting DMG for notarization (this takes 1-5 minutes)..."

    local submit_output
    submit_output=$(xcrun notarytool submit "$dmg_path" \
        --apple-id "$TOKEN_GATE_APPLE_ID" \
        --password "$TOKEN_GATE_APPLE_PASSWORD" \
        --team-id "$TOKEN_GATE_APPLE_TEAM_ID" \
        --wait 2>&1)

    echo "$submit_output"

    if echo "$submit_output" | grep -q "status: Accepted"; then
        info "Notarization successful!"
    else
        error "Notarization failed! Check the output above for details."
    fi

    info "Stapling notarization ticket..."
    xcrun stapler staple "$dmg_path"
    info "Notarization ticket stapled"
}

# --- Step 8: Output checksum ---
checksum() {
    local dmg_path="$1"
    info "SHA256 checksum:"
    shasum -a 256 "$dmg_path"
}

# --- Main ---
main() {
    local version
    version=$(get_version "${1:-}")
    info "Building TokenGate v${version} for macOS"

    check_prereqs
    build_go_binary
    build_flutter_app
    sign_app
    verify_signature

    local dmg_path
    dmg_path=$(create_dmg "$version")
    sign_dmg "$dmg_path"
    notarize_dmg "$dmg_path"
    checksum "$dmg_path"

    echo ""
    info "========================================="
    info "  Build complete!"
    info "  DMG: $dmg_path"
    info "  Version: $version"
    info "  Signed + Notarized"
    info "========================================="
}

main "$@"
