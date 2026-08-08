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

## Installing

```sh
brew tap khatri-viren/sanepeek https://github.com/khatri-viren/sanepeek
brew trust --cask khatri-viren/sanepeek/sanepeek
brew install --cask sanepeek
```

(On Homebrew versions without `brew trust`, skip that line and run
`brew install --cask --no-quarantine sanepeek` instead.)

Or grab the DMG from [Releases](https://github.com/khatri-viren/sanepeek/releases).

SanePeek is signed ad-hoc rather than notarized, because notarization requires a paid
Apple Developer Program membership. macOS will therefore say it cannot verify the
developer the first time you open a downloaded copy: open **System Settings → Privacy &
Security**, scroll down, and click **Open Anyway**. Trusting the cask above skips that
step by never applying the quarantine attribute in the first place.

Once installed, SanePeek updates itself through [Sparkle](https://sparkle-project.org) —
Settings → Updates has the current version and a manual check.

## Requirements

- macOS 15.0 or later
- Xcode 26 or later — the popup's Liquid Glass path compiles against the macOS 26 SDK,
  behind an availability check, so the app still runs on macOS 15

## Building and running

```sh
open SanePeek.xcodeproj
```

Build and run the `SanePeek` scheme (⌘R). The app is not sandboxed: reading the SMC for
temperature and IOKit power sources for battery both require access the App Sandbox does
not grant, which is also why SanePeek is distributed directly rather than through the
Mac App Store.

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

With two menu bar items enabled (CPU + Temperature), a head-to-head against
[Stats](https://github.com/exelban/stats) — both Release builds, both idle, sampled for
3 minutes (36 samples at 5s intervals) on the same machine — looked like this:

| Metric | Stats | SanePeek |
|---|---|---|
| CPU (avg) | 6.75% | 0.44% — **15.3× less** |
| Memory (avg RSS) | 250.0 MB | 26.2 MB — **9.5× less** |
| Energy impact (avg) | 7.33 | 0.30 — **24.4× less** |

Numbers were captured with `top -l 36 -s 5` for CPU/memory and `sudo powermetrics
--samplers tasks --show-process-energy` for energy impact. Each app's widget/helper
process was excluded so the comparison is core menu-bar process to core menu-bar
process.

## Releasing

Releases are cut by tag. `.github/workflows/release.yml` builds, packages, publishes the
GitHub Release, updates the Sparkle appcast, and bumps the Homebrew cask:

```sh
git tag v1.1.0
git push --tags
```

### One-time setup

1. **Sparkle signing key.** Already generated; the public half is in `Config/Info.plist`
   under `SUPublicEDKey` and the private half is in the maintainer's login Keychain.
   Never change it: installed copies trust only the key baked into their own bundle, so a
   new key orphans every existing install and they can only be updated by reinstalling.

   The tooling ships with the Swift package, at
   `…/DerivedData/SanePeek-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`. Re-print the
   public key with `./generate_keys -p`, or export the private key for CI with
   `./generate_keys -x private-key.txt`.

2. **`SPARKLE_PRIVATE_KEY` secret.** Export the private key as above and paste the file's
   contents into a repository secret of that name, then delete the file. Anyone holding it
   can sign an update that every install will download and run, and because the app isn't
   notarized, Apple's revocation is not a backstop.

3. **GitHub Pages.** Enable Pages for the repository, serving from the `gh-pages` branch.
   The workflow publishes `appcast.xml` there, and `SUFeedURL` points at it. Sparkle polls
   that one URL forever, so it must not move.

4. **`CASK_PUSH_TOKEN` secret.** `main` is protected by a ruleset, and the cask bump step
   pushes to it. `GITHUB_TOKEN` cannot get through: the only bypass actor is the repository
   owner, and GitHub refuses to add the Actions app as a bypass actor on a personal repo
   (`Actor GitHub Actions integration must be part of the ruleset source or owner
   organization`). Create a fine-grained PAT limited to this repository with
   **Contents: Read and write**, and store it as `CASK_PUSH_TOKEN`. Pushing as the owner
   bypasses the ruleset.

   Without it the release still publishes; only the cask bump is skipped, with a warning,
   leaving Homebrew users on the previous version.

Until `SPARKLE_PRIVATE_KEY` is set the workflow still builds and publishes the DMG; it just
skips the appcast and logs a warning, so existing users won't be offered the update.

## License

SanePeek is available under the MIT license. See [LICENSE](LICENSE) for details.
