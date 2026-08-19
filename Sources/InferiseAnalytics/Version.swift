//
//  Version.swift
//  InferiseAnalytics
//

/// The package's released version — the single source of truth.
///
/// Bump this by hand as part of the change that warrants it, then `make tag`,
/// which reads this value and creates the matching annotated git tag.
///
/// It is also reported on every event as `context.library.version`, so the
/// ingest side can tell which SDK build produced a given payload.
///
/// Starts at 1.0.0. The upstream fork carried 1.9.4, but that described
/// Segment's code — nothing has ever been released from this repository, so
/// there is no version history to continue and no published tag to order
/// against.
///
/// BREAKING.FEATURE.FIX
let packageVersion: String = "1.0.0"
