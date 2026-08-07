# SanePeek

A native macOS system monitor that gives you the essential answers about your Mac —
CPU, memory, storage, network, battery, temperature, and GPU — without the clutter,
complexity, or resource usage of traditional monitoring tools.

> Monitor your Mac. Do not become its biggest process.

## Features

- **Menu bar items** — a live number or level-bar reading for any metric you enable,
  right in the menu bar. Pick per-metric which ones show and how.
- **Glance popup** — click a menu bar item for a Control Center–style popup: every
  metric as a tab, with its own history chart, one click away.
- **Dashboard** — a full window with a card for every metric: CPU, memory, storage,
  network, battery, temperature, and GPU (GPU hides gracefully when unsupported).
- **Runs as an accessory app** — lives in the menu bar with no Dock icon by default;
  a Dock icon appears only while the dashboard window is open.
- **Configurable** — refresh rate (1s/2s/5s), decimal or binary byte units, Celsius or
  Fahrenheit, light/dark/system appearance, and launch at login.
- **Genuinely light**: idle CPU and memory footprint are treated as a feature, not an
  afterthought — see [Performance](#performance) below.

## Requirements

- macOS 15.0 or later
- Xcode 16 or later (Swift 6, SwiftUI, Swift Testing)

## Building and running

```sh
open SanePeek.xcodeproj
```

Build and run the `SanePeek` scheme (⌘R). The app is sandboxed and requests no special
entitlements beyond what's needed to read system metrics.

To build from the command line:

```sh
xcodebuild build -project SanePeek.xcodeproj -scheme SanePeek -destination 'platform=macOS'
```

## Testing

Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing); UI
tests use XCTest.

```sh
xcodebuild test -project SanePeek.xcodeproj -scheme SanePeek -destination 'platform=macOS'
```

## Architecture

- **SwiftUI views** render presentation-ready models — no direct system calls.
- **View models** (`@Observable`) adapt engine snapshots into per-card display state.
- **`MetricsEngine`** is the single actor that owns polling, cadence, and bounded
  history for every metric, shared by the dashboard, popups, and menu bar items.
- **Metric readers** wrap the underlying system APIs (Mach host stats, IOKit,
  SystemConfiguration, `NWPathMonitor`, …) behind small, independently testable
  protocols.

## Performance

SanePeek is built on the premise that a system monitor should not itself show up as a
system load. In its default configuration (one menu bar item, dashboard closed) it runs
at roughly **0.25% average CPU** and a **24 MB** physical footprint, measured over a
120-second steady-state window on a Release build. Both the dashboard window and any
closed menu bar popup are fully inert — no rendering work happens for content the user
can't see — and polling pauses outright when the display sleeps or the session locks.

## License

SanePeek is available under the MIT license. See [LICENSE](LICENSE) for details.
