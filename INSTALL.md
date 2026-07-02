# Install Agent Usage (menu bar app)

A tiny macOS menu bar app that shows your **Cursor** and **Claude Code**
usage, cycling between the two. It reads your **already signed-in Cursor
app** and your **local Claude Code logs** — nothing to paste for either.

Requirements: macOS 13+. Cursor stats need the Cursor app installed and
signed in; Claude stats need Claude Code to have run locally at least once.

## Install

1. Download `AgentUsage.zip` and unzip it.
2. Drag **AgentUsage** into your **Applications** folder.
3. Double-click to open.

Or via Homebrew (see the main README) for a one-line install + easy updates.

## Tips

- Click the menu bar icon to see both providers' usage, expandable per-model
  breakdowns, and spend against your Cursor limit.
- Gear menu → **Show in menu bar** to pin the label to Cursor only, Claude
  only, or let it keep cycling between both.
- Gear menu → **Launch at login** to keep it running automatically.
- The Cursor icon turns **orange** past 70% and **red** past 90% of your
  limit.
