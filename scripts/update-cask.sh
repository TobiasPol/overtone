#!/usr/bin/env bash
# Writes the Homebrew cask for a released version into a tap checkout.
# Usage: scripts/update-cask.sh <version> <sha256> <path-to-homebrew-tap>
set -euo pipefail
VERSION="${1:?usage: scripts/update-cask.sh <version> <sha256> <tap-dir>}"
SHA256="${2:?missing sha256}"
TAP="${3:?missing tap directory}"
REPO="${OVERTONE_REPO:-TobiasPol/overtone}"

mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/overtone.rb" <<CASK
cask "overtone" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/Overtone-#{version}.zip"
  name "Overtone"
  desc "Menu bar system-wide equalizer with AutoEQ, spatial audio and per-app volume"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Overtone.app"

  uninstall quit: "com.tobiaspol.overtone"

  zap trash: "~/Library/Application Support/Overtone"

  caveats <<~EOS
    Overtone lives in the menu bar (no Dock icon). On first launch, allow
    "System Audio Recording" when macOS asks.

    Releases are not notarized yet, so macOS blocks the very first launch.
    Open System Settings → Privacy & Security and click "Open Anyway",
    or clear the download quarantine yourself:
      xattr -dr com.apple.quarantine "#{appdir}/Overtone.app"
  EOS
end
CASK
echo "✓ Wrote $TAP/Casks/overtone.rb ($VERSION)"
