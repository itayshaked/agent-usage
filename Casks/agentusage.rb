cask "agentusage" do
  version "1.4"
  sha256 "53872b4a7d44477b39a2bcbc9daeaca29357a071b3b9805778ea8f46c161ac2a"

  # Points at this repo's own GitHub Release asset. Scripts/cut_release.sh
  # tags a release, uploads the zip, and prints the version/sha256 to paste
  # here.
  url "https://github.com/itayshaked/agent-usage/releases/download/v#{version}/AgentUsage.zip"
  name "Agent Usage"
  desc "Menu bar app showing Cursor and Claude Code usage/spend"
  homepage "https://github.com/itayshaked/agent-usage"

  depends_on macos: :ventura

  # Signed with a Developer ID and notarized by Apple, so no quarantine
  # workaround is needed — `brew install` just works.
  app "AgentUsage.app"

  zap trash: [
    "~/Library/Preferences/com.local.agentusage.plist",
  ]
end
