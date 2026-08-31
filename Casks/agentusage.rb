cask "agentusage" do
  version "1.5"
  sha256 "19b320aa57e4b829d32e8926b46b19feef1bda82583a062035e3a6379123c232"

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
