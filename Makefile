.PHONY: build test install clean signing-check
build:
	./scripts/build.sh
test:
	swift test
	./scripts/test-packaging.sh
	./scripts/test-service-state.sh
install: build
	./scripts/install.sh
signing-check:
	./scripts/check-signing.sh
clean:
	rm -rf build .build

