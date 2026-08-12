# SanePeek test suite

The `SanePeek` test plan is the reproducible entry point for the correctness, UI, and
performance targets. Commands below assume the current directory is the repository root.

## Correctness tests

```sh
xcodebuild test \
  -project SanePeek.xcodeproj \
  -scheme SanePeek \
  -testPlan SanePeek \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:SanePeekTests \
  -skip-testing:SanePeekTests/SMCTemperatureAdapterHardwareTests \
  -enableCodeCoverage YES \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  -collect-test-diagnostics on-failure
```

The hardware temperature adapter suite is intentionally excluded from deterministic
correctness runs. It requires a supported physical SMC device and is run explicitly when
hardware evidence is needed:

```sh
xcodebuild test \
  -project SanePeek.xcodeproj \
  -scheme SanePeek \
  -testPlan SanePeek \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:SanePeekTests/SMCTemperatureAdapterHardwareTests \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  -collect-test-diagnostics on-failure
```

## UI tests

```sh
xcodebuild test \
  -project SanePeek.xcodeproj \
  -scheme SanePeek \
  -testPlan SanePeek \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:SanePeekUITests \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  -collect-test-diagnostics on-failure
```

UI tests launch isolated defaults suites and deterministic preview fixtures. The harness
uses bounded waits, terminates the application, and asserts that both the app process and
the suite defaults are cleaned up. UI jobs run serially because the menu-bar and settings
journeys share system-level application surfaces. The launch-at-login interaction remains
manual-only when the operating system does not expose a reliable test control; the fake
service and disabled-state tests cover normal automated behavior.

## Performance tests

```sh
xcodebuild test \
  -project SanePeek.xcodeproj \
  -scheme SanePeek \
  -testPlan SanePeek \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:SanePeekPerformanceTests \
  -enablePerformanceTestsDiagnostics YES \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  -collect-test-diagnostics on-failure
```

The checked-in baseline is
`Performance/Baselines/macos-arm64-2026-08-12.json`. It records the median of five
XCTest measurements for deterministic engine sampling and merge, active metric filtering,
coherent view-model ticks, menu-bar number/bar rendering, and monitor content handoff.
The 20% regression budget is a review budget for performance runs; ordinary correctness
tests do not fail on noisy wall-clock measurements.

## Diagnostics and flake handling

All suites enable XCTest timeouts and collect diagnostics on failure. Result bundles and
logs should be retained by CI rather than automatically retried, so a flaky failure keeps
its first-failure evidence. When investigating a failure, inspect the `.xcresult` bundle,
test diagnostics, application log, and the test's deterministic fixture before changing a
timeout. Cleanup assertions are part of the UI harness and should identify leaked app
processes or persistent test defaults at the failing test's cleanup line.

## Release rehearsal

```sh
xcodebuild build \
  -project SanePeek.xcodeproj \
  -scheme SanePeek \
  -configuration Debug \
  -destination 'platform=macOS'

xcodebuild build \
  -project SanePeek.xcodeproj \
  -scheme SanePeek \
  -configuration Release \
  -destination 'platform=macOS'

git diff --check
```

The rehearsal also runs the correctness and UI commands above, records their result-bundle
paths, and records the Xcode version, host architecture, skipped suites, and manual-only
checks in the Cortex task note. Release sign-off requires separate Instruments review with
Time Profiler, Allocations, SwiftUI, and Power Profiler, plus a documented multi-hour/day
idle observation. Those checks cannot be substituted with a short automated performance
test; the sign-off record must state explicitly which of them were collected for each
release candidate.
