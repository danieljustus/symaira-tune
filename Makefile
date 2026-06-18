BINARY := symtune

.PHONY: build release test lint run doctor serve clean

build:
	swift build

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
