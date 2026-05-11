.PHONY: build release-binaries clean

build:
	cd ../web && npm install && npm run build
	mkdir -p ./internal/web/dist
	cp -r ../web/dist/ ./internal/web/dist/
	go build -o token_gate .

# Cross-compile all platforms and package into tarballs.
# Called by scripts/release.sh — do not run manually.
release-binaries:
	cd ../web && npm install && npm run build
	mkdir -p ./internal/web/dist
	cp -r ../web/dist/ ./internal/web/dist/
	GOOS=darwin GOARCH=arm64 go build -o token_gate_darwin_arm64 .
	GOOS=darwin GOARCH=amd64 go build -o token_gate_darwin_amd64 .
	GOOS=linux  GOARCH=amd64 go build -o token_gate_linux_amd64  .
	GOOS=linux  GOARCH=arm64 go build -o token_gate_linux_arm64  .
	tar -czf token_gate_darwin_arm64.tar.gz token_gate_darwin_arm64
	tar -czf token_gate_darwin_amd64.tar.gz token_gate_darwin_amd64
	tar -czf token_gate_linux_amd64.tar.gz  token_gate_linux_amd64
	tar -czf token_gate_linux_arm64.tar.gz  token_gate_linux_arm64
	@echo ""
	@echo "SHA256:"
	@shasum -a 256 token_gate_darwin_arm64.tar.gz token_gate_darwin_amd64.tar.gz \
	               token_gate_linux_amd64.tar.gz  token_gate_linux_arm64.tar.gz

clean:
	rm -f token_gate token_gate_darwin_arm64 token_gate_darwin_amd64 token_gate_linux_amd64 token_gate_linux_arm64
	rm -f token_gate_darwin_arm64.tar.gz token_gate_darwin_amd64.tar.gz token_gate_linux_amd64.tar.gz token_gate_linux_arm64.tar.gz
	rm -rf internal/web/dist/
