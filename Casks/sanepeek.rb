# Homebrew cask for SanePeek.
#
# This repo doubles as its own tap, so no second repository is needed — `brew tap` accepts
# an explicit URL for repos not named `homebrew-*`:
#
#   brew tap khatri-viren/sanepeek https://github.com/khatri-viren/sanepeek
#   brew install --cask --no-quarantine sanepeek
#
# `--no-quarantine` matters here: SanePeek is ad-hoc signed rather than notarized, so
# without it Gatekeeper quarantines the app and the first launch needs a trip through
# System Settings. Homebrew skips that when the quarantine attribute is never applied.
#
# `version` and `sha256` are rewritten by .github/workflows/release.yml on every release.
cask "sanepeek" do
  version "1.0.1"
  sha256 "38178122e9bda7c676a5eeae64d35da9edcc98434c57b548091bc0f15106eb1c"

  url "https://github.com/khatri-viren/sanepeek/releases/download/v#{version}/SanePeek-#{version}.dmg"
  name "SanePeek"
  desc "Native macOS system monitor for CPU, memory, storage, network, battery, and temperature"
  homepage "https://github.com/khatri-viren/sanepeek"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "SanePeek.app"

  # The app is an accessory that keeps running in the menu bar, so it has to be stopped
  # before the bundle is replaced or removed.
  uninstall quit: "com.sanepeek.SanePeek"

  zap trash: [
    "~/Library/Preferences/com.sanepeek.SanePeek.plist",
    "~/Library/Caches/com.sanepeek.SanePeek",
    "~/Library/HTTPStorages/com.sanepeek.SanePeek",
  ]
end
