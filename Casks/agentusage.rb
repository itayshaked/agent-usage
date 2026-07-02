cask "agentusage" do
  version "1.2"
  sha256 "be76de9a61177f1b4538d5374d448b2ca1f9b76e7bef0c6fe83394d8a4274c70"

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
