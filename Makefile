###############################################
#
# Makefile — InferiseAnalytics
#
# Self-contained: build / test / clean this Swift package on its own.
# Client apps consume it via a package reference; releases are cut with
# `make tag` after bumping Version.swift.
#
###############################################

.DEFAULT_GOAL := build

# Swift sources to format and lint.
#
# Deliberately NOT `Sources Tests`. Sources/ also holds vendored third-party
# code — Sovran (MIT) and JSONSafeEncoding (Apache 2.0) — which must be left
# byte-identical to upstream. Reformatting them would produce a diff against
# the version recorded in each VENDORED.md, and Apache 2.0 §4(b) requires
# modified files to carry a notice of the change. Scope to our own module.
SOURCES := Sources/InferiseAnalytics Tests

repo:
	open https://github.com/inferise/analytics-swift

# Open the package in Xcode (SPM manifest; no .xcodeproj needed).
open:
	xed .

# Build the package.
.PHONY: build
build:
	swift build

# Run the package's unit tests.
.PHONY: test
test:
	swift test

# Remove the package's build artifacts (.build).
.PHONY: clean
clean:
	swift package clean

# ---------------------------------------------
# Lint & Format
# ---------------------------------------------

# Format then lint.
fmt: format lint
	echo "Done"

# Full pre-commit gate: format, lint, build, then test.
.PHONY: validate
validate: format lint build test
	echo "✅ validate passed: format, lint, build, test all green"

# Format the Swift sources against the shared config.
format:
	swiftformat --config styleguide/swiftformat.cfg $(SOURCES)

# Lint the Swift sources against the shared config.
# --strict promotes warnings to errors: SwiftLint otherwise exits 0 on
# warning-severity rules, so `validate` would pass with violations outstanding.
lint:
	swiftlint lint --strict --config styleguide/swiftlint.yml $(SOURCES)

# ---------------------------------------------
# Documentation
# ---------------------------------------------

# Port the documentation server binds to.
DOCS_PORT := 8000
# The page to open — a DocC site renders under /documentation/<module>, not the root shell.
DOCS_URL := http://localhost:$(DOCS_PORT)/documentation/inferiseanalytics

# Build the DocC documentation from the library's `///` headerdoc, then serve it over
# HTTP and open it in the browser. A DocC site is a JS app with absolute paths, so it
# must be served (opening ./docs/index.html directly shows a blank page); this target
# does the whole build + serve + launch. `xcrun` lets the plugin find `docc` in the
# Xcode toolchain. `--symbol-graph-minimum-access-level internal` documents the
# internal types too (Storage, HTTPClient, the retry state machine), not just the
# public API. The browser opens once the port is listening; Ctrl-C stops the server.
.PHONY: docs
docs:
	xcrun swift package --allow-writing-to-directory docs generate-documentation --target InferiseAnalytics --symbol-graph-minimum-access-level internal --output-path docs
	@echo "📚 Serving $(DOCS_URL)  (Ctrl-C to stop)"
	@( until nc -z localhost $(DOCS_PORT) 2>/dev/null; do sleep 1; done; open "$(DOCS_URL)" ) &
	@python3 -m http.server -d docs $(DOCS_PORT)

# ---------------------------------------------
# Release tagging
# ---------------------------------------------

# The released version, read from Version.swift (the source of truth).
VERSION := $(shell sed -n 's/.*packageVersion: String = "\(.*\)".*/\1/p' Sources/InferiseAnalytics/Version.swift)

# Create an annotated git tag matching the Version.swift version (e.g. 1.0.0), then push it.
#
# Bump Version.swift first — it is what this reads, and it is also what every
# event reports as context.library.version, so a tag that disagrees with it
# makes shipped data impossible to trace back to a build.
.PHONY: tag
tag:
	git tag -a "$(VERSION)" -m "$(VERSION)"
	git push --tags

# Print the version this would tag, without tagging. Useful as a pre-flight check.
.PHONY: version
version:
	@echo "$(VERSION)"


# Tag, push, and publish a GitHub Release in one step. Depends on `tag` rather
# than duplicating its logic, so the release always uses the exact same
# version string that got tagged -- no chance of the two drifting apart.
.PHONY: gh-release
gh-release: tag
	gh release create "$(VERSION)" --title "$(VERSION)" --generate-notes

# ---------------------------------------------
# Submodules
# ---------------------------------------------

# Add the shared styleguide submodule.
substyle:
	git submodule add git@github.com:inferise/styleguide.git styleguide

# Add the control wiki submodule.
subwiki:
	git submodule add git@github.com:inferise/analytics-swift.wiki.git wiki

# Initialize and update all submodules.
subpull:
	git submodule update --init --recursive
