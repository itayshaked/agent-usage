cask "cursorusagebar" do
  version "1.0"
  sha256 "f7fd6ad1142665deb6608273d1250797e62cc8619285f69c830ed9b7da6d5c99"

  # Points at this repo's own GitHub Release asset. Scripts/cut_release.sh
  # tags a release, uploads the zip, and prints the version/sha256 to paste
  # here.
  url "https://github.com/itayshaked/cursor-usage-bar/releases/download/v#{version}/CursorUsageBar.zip"
  name "Cursor Usage"
  desc "Menu bar app showing Cursor usage/spend against your limit"
  homepage "https://github.com/itayshaked/cursor-usage-bar"

  depends_on macos: ">= :ventura"

  # Signed with a Developer ID and notarized by Apple, so no quarantine
  # workaround is needed — `brew install` just works.
  app "CursorUsageBar.app"

  zap trash: [
    "~/Library/Preferences/com.local.cursorusagebar.plist",
  ]
end
