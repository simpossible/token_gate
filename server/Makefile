.PHONY: build clean

build:
	cd ../web && npm install && npm run build
	mkdir -p ./internal/web/dist
	cp -r ../web/dist/ ./internal/web/dist/
	go build -o token_gate .

clean:
	rm -f token_gate
	rm -rf internal/web/dist/
