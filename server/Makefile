.PHONY: build release-binaries clean app windows-app

BUILD_ID := $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")

build:
	go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate .

# Build the Flutter desktop app for the current platform.
# Compiles the Go binary first so it can be embedded in assets/bin/.
app:
	$(MAKE) build
	@mkdir -p ../app/assets/bin
	@cp token_gate ../app/assets/bin/token_gate
	@echo '$(BUILD_ID)' > ../app/assets/bin/build_id.txt
	cd ../app && flutter build macos
	@echo ""
	@echo "Built: app/build/macos/Build/Products/Release/app.app"

# Cross-compile the Go binary for Windows and build the Flutter Windows app.
# Run this from a Windows machine (or WSL with a Windows Flutter toolchain).
windows-app:
	GOOS=windows GOARCH=amd64 go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate_windows_amd64.exe .
	@mkdir -p ../app/assets/bin
	@cp token_gate_windows_amd64.exe ../app/assets/bin/token_gate.exe
	@echo '$(BUILD_ID)' > ../app/assets/bin/build_id.txt
	cd ../app && flutter build windows
	@echo ""
	@echo "Built: app/build/windows/x64/runner/Release/"

# Build the Windows installer (requires Inno Setup).
# Run this from a Windows machine.
# Usage: make windows-installer VERSION=2.0.0
windows-installer:
	@$(MAKE) windows-app
	@if command -v iscc >/dev/null 2>&1; then \
		cd ../scripts && \
		iscc /O../build /F"TokenGate-$(VERSION)-setup" /DTOKEN_GATE_VERSION="$(VERSION)" installer.iss; \
		echo ""; \
		echo "Built: build/TokenGate-$(VERSION)-setup.exe"; \
	else \
		echo "Error: Inno Setup Compiler (iscc) not found"; \
		echo "Install via: winget install JRSoftware.InnoSetup"; \
		exit 1; \
	fi

# Cross-compile all platforms and package into tarballs/zips.
# Called by scripts/release.sh — do not run manually.
release-binaries:
	GOOS=darwin  GOARCH=arm64 go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate_darwin_arm64  .
	GOOS=darwin  GOARCH=amd64 go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate_darwin_amd64  .
	GOOS=linux   GOARCH=amd64 go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate_linux_amd64   .
	GOOS=linux   GOARCH=arm64 go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate_linux_arm64   .
	GOOS=windows GOARCH=amd64 go build -ldflags "-X main.buildID=$(BUILD_ID)" -o token_gate_windows_amd64.exe .
	tar -czf token_gate_darwin_arm64.tar.gz token_gate_darwin_arm64
	tar -czf token_gate_darwin_amd64.tar.gz token_gate_darwin_amd64
	tar -czf token_gate_linux_amd64.tar.gz  token_gate_linux_amd64
	tar -czf token_gate_linux_arm64.tar.gz  token_gate_linux_arm64
	zip      token_gate_windows_amd64.zip   token_gate_windows_amd64.exe
	@echo ""
	@echo "SHA256:"
	@shasum -a 256 token_gate_darwin_arm64.tar.gz token_gate_darwin_amd64.tar.gz \
	               token_gate_linux_amd64.tar.gz  token_gate_linux_arm64.tar.gz \
	               token_gate_windows_amd64.zip

clean:
	rm -f token_gate token_gate_darwin_arm64 token_gate_darwin_amd64 token_gate_linux_amd64 token_gate_linux_arm64 token_gate_windows_amd64.exe
	rm -f token_gate_darwin_arm64.tar.gz token_gate_darwin_amd64.tar.gz token_gate_linux_amd64.tar.gz token_gate_linux_arm64.tar.gz token_gate_windows_amd64.zip
