BINARY := symtune

.PHONY: build build-app smoke-app release test lint run doctor serve clean

build:
	swift build

build-app:
	./scripts/build-app.sh

smoke-app: build-app
	./scripts/smoke-app.sh build/app/SymairaTune.app

release:
	swift build -c release

test:
	swift test

lint:
	@command -v swiftlint >/dev/null 2>&1 && swiftlint --quiet || echo "swiftlint not installed; skipping"

run: build
	swift run -q $(BINARY) doctor

doctor: build
	swift run -q $(BINARY) doctor

serve: build
	swift run -q $(BINARY) serve

clean:
	swift package clean
	rm -rf .build
