# Releasing

`Sources/InferiseAnalytics/Version.swift` is the single source of truth for the
version. The git tag, the GitHub release, and the `context.library.version`
field on every event all read from it — a tag that disagrees with it makes
shipped data impossible to trace back to a build.

## Steps

1. Bump `packageVersion` (BREAKING.FEATURE.FIX) in
   `Sources/InferiseAnalytics/Version.swift` as part of the change that
   warrants it, and commit the bump with that change.
2. Pre-flight check: `make version` prints the version that would be tagged,
   without tagging.
3. `make tag` — creates an annotated git tag matching the version and pushes
   it.
4. `make gh-release` — runs `make tag`, then
   `gh release create <version> --generate-notes`. It depends on `tag` rather
   than duplicating it, so the release always uses the exact version string
   that got tagged.

## Binary distribution

For consumers that cannot use SPM, `./build.sh` builds and zips the
`InferiseAnalytics`, `Sovran`, and `JSONSafeEncoding` XCFrameworks (iOS, macOS,
Mac Catalyst, tvOS, watchOS) with sha256 checksums. It requires the
`swift-create-xcframework` tool (install via Mint).
