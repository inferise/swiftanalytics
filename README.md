# InferiseAnalytics

Analytics for Swift apps — iOS, iPadOS, macOS, tvOS, watchOS, visionOS, and Linux.
Events are captured on-device, batched to disk, and uploaded to Inferise's own
ingest API. Nothing leaves the device for anywhere else.

```swift
import InferiseAnalytics

let analytics = Analytics(
    configuration: Configuration(writeKey: "<WRITE KEY>")
        .flushAt(20)
        .flushInterval(30)
)

analytics.identify(userId: "u1", traits: ["email": "person@example.com"])
analytics.track(name: "Order Completed", properties: ["price": 99.84])
analytics.screen(title: "Checkout")
```

## How it works

Events pass through a **timeline** of plugins — `.before`, `.enrichment`,
`.destination`, `.after` — which is where you hook in to add context, redact
fields, or fan out to another vendor's SDK. The built-in `InferiseDestination`
writes events to a file-backed queue and uploads them in batches, with retry and
backoff driven by the server's response codes.

On startup the SDK fetches a settings document from the ingest API. That document
controls which destinations are enabled, can repoint the SDK at a different ingest
host without an app release, and configures retry behavior.

The wire contract — batch envelope, settings shape, and response codes — is
specified in the [aws-analytics](../aws-analytics/README.md) service, which is the
normative definition for every language SDK.

## Configuration

`Configuration` is a builder; every option has a sensible default.

| Option | Default | Notes |
| --- | --- | --- |
| `flushAt` | 20 | events queued before an automatic upload |
| `flushInterval` | 30s | time-based upload trigger |
| `apiHost` / `cdnHost` | Inferise ingest | override for a proxy, a region, or a different backend entirely |
| `storageMode` | `.disk` | also `.memory(_)`, `.diskAtURL(_)`, or a custom `DataStore` |
| `operatingMode` | `.asynchronous` | use `.synchronous` in short-lived processes |
| `requestFactory` | none | mutate outbound `URLRequest`s (extra headers, proxying) |
| `httpSession` | `URLSession` | swap the transport wholesale |
| `httpConfig` | from settings | rate-limit and backoff policy |
| `anonymousIdGenerator` | UUID | supply your own scheme |
| `setTrackedApplicationLifecycleEvents` | `.all` | opt in/out per lifecycle event |

`apiHost` and `cdnHost` are the seam that makes moving to a different backend a
config change rather than a rewrite.

## Plugins

```swift
analytics.add(plugin: MyEnrichment())
analytics.add(enrichment: { event in /* mutate or drop */ event })
```

See [`Examples/other_plugins`](Examples/other_plugins) for working plugins
(IDFA collection, consent gating, UIKit screen tracking) and
[`Examples/destination_plugins`](Examples/destination_plugins) for the shape a
device-mode destination takes.

Device-mode destinations for third-party vendors (Firebase, Mixpanel, Amplitude,
…) are not yet ported. Each is a `DestinationPlugin` that forwards events into
that vendor's SDK; `ExampleDestination.swift` is the template.

## Vendored dependencies

`Sovran` (state store) and `JSONSafeEncoding` (NaN/Infinity-safe JSON) are
vendored under `Sources/` rather than fetched, so the package has no external
dependencies. Each carries its upstream license and a `VENDORED.md` recording
origin, version, and any local modifications.

## Examples

[`Examples/apps`](Examples/apps) covers UIKit, SwiftUI, macOS, watchOS, and
app-extension/widget setups.

## Contributing

See the [contributing guide](CONTRIBUTING.md), and the
[code of conduct](CODE_OF_CONDUCT.md).

## License

This project is a fork of [analytics-swift](https://github.com/segmentio/analytics-swift).
The original MIT license and copyright notice are retained below as that license
requires, and apply to the upstream-derived portions of this code.

```
MIT License

Copyright (c) 2021 Segment

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
