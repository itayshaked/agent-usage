# Agent Usage

A native macOS menu bar app that shows your **Cursor** and **Claude Code**
usage — requests, spend, and per-model breakdowns — right from the top bar.
The menu bar label cycles between the two, or you can pin it to just one.

## Install

```bash
brew tap itayshaked/agent-usage https://github.com/itayshaked/agent-usage.git
brew install --cask agentusage
```

Then launch **AgentUsage** from Spotlight (or `open -a AgentUsage`). A menu
bar icon appears, cycling between the Cursor and Claude brand marks.

**Updating:**
```bash
brew update && brew upgrade --cask agentusage
```

Prefer a manual install? Grab the zip from the
[latest release](https://github.com/itayshaked/agent-usage/releases/latest),
unzip it, and drag **AgentUsage** into `/Applications`.

## Cursor

Works out of the box with **zero config** — it reads your already signed-in
Cursor app. It only ever talks to `cursor.com`.

> These endpoints are **unofficial** (reverse-engineered from the dashboard)
> and may change or break without notice.

**What it shows:**
- Account email and plan
- Current billing cycle
- Requests used / limit (with a progress bar)
- Spend this cycle
- Per-model breakdown (spend or request count)

If auto mode can't find your Cursor login, you can paste a session token
manually via the gear menu → **Cursor** → **Change token…**:

1. Open <https://cursor.com/dashboard/usage> while logged in.
2. Open DevTools (⌥⌘I) → **Application** → **Cookies** → `https://cursor.com`.
3. Copy the **value** of `WorkosCursorSessionToken` (looks like
   `user_01…%3A%3AeyJ…`) and paste it in.

The token is a JWT with an expiry; when it lapses you'll see an auth error —
just paste a fresh one the same way.

## Claude Code

Also **zero config** — reads your local Claude Code session logs
(`~/.claude/projects/`). No auth, no tokens, nothing to paste. Costs are
estimated from token counts using Anthropic's published per-model pricing.

**What it shows:**
- Today's and this month's estimated spend
- Token totals
- Per-model breakdown

Want org-wide billing instead of just this Mac's usage? Set an Anthropic
Admin API key (`sk-ant-admin…`) via the gear menu → **Claude** → **Set Admin
API key…**.

## Tips

- Click the menu bar icon to expand either provider's per-model breakdown.
- Gear menu → **Show in menu bar** to pin the label to Cursor only, Claude
  only, or keep it cycling between both.
- Gear menu → **Launch at login** to keep it running automatically.
- Both providers auto-refresh every 10 minutes; refresh manually with the ↻
  button.
- The Cursor icon turns **orange** past 70% and **red** past 90% of your
  limit.

## Notes

- No dock icon, menu bar only.
- Cursor token / Claude Admin key live in the macOS Keychain, never on disk
  in plaintext.
- Requires macOS 13+.

## Building from source

```bash
git clone https://github.com/itayshaked/agent-usage.git
cd agent-usage
./Scripts/build_app.sh
open build/AgentUsage.app
```

See `Scripts/` for the release build (`make_dist.sh`) and release-cutting
(`cut_release.sh`) scripts used to publish new versions.
