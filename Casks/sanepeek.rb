# Homebrew cask for SanePeek.
#
# This repo doubles as its own tap, so no second repository is needed — `brew tap` accepts
# an explicit URL for repos not named `homebrew-*`:
#
#   brew tap khatri-viren/sanepeek https://github.com/khatri-viren/sanepeek
#   brew trust --cask khatri-viren/sanepeek/sanepeek
#   brew install --cask sanepeek
#
# Trusting the cask matters here: SanePeek is ad-hoc signed rather than notarized, so
# an untrusted install leaves Gatekeeper to quarantine the app and the first launch
# needs a trip through System Settings. Trusting it skips that — same effect as the
# `--no-quarantine` install flag Homebrew removed when it added the tap-trust model;
# on Homebrew versions predating that model, use `brew install --cask --no-quarantine
# sanepeek` instead.
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

  depends_on macos: :sequoia

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
