# Agent Usage

A native macOS menu bar app that shows your **Cursor** and **Claude Code**
usage — requests, spend, and per-model breakdowns — right from the top bar.
The menu bar label cycles between the two, or you can pin it to just one.

## Cursor

Authenticates the same way the Cursor web dashboard does — with your
`WorkosCursorSessionToken` browser cookie, stored securely in your macOS
Keychain — or automatically, by reading your already signed-in Cursor app.
It only ever talks to `cursor.com`.

> These endpoints are **unofficial** (reverse-engineered from the dashboard)
> and may change or break without notice.

### What it shows

- Account email and plan (membership type)
- Current billing cycle
- Requests used / limit (with a progress bar)
- Spend this cycle (from aggregated usage events)
- Per-model breakdown (spend or request count)

### Get your session token (manual mode)

Auto mode (reading your signed-in Cursor app) needs no setup. If you'd rather
paste a token manually:

1. Open <https://cursor.com/dashboard/usage> while logged in.
2. Open DevTools (⌥⌘I) → **Application** → **Cookies** → `https://cursor.com`.
3. Copy the **value** of `WorkosCursorSessionToken` (looks like
   `user_01…%3A%3AeyJ…`).
4. Paste it into the app and hit **Save**.

The token is a JWT with an expiry; when it lapses you'll see an auth error and
just paste a fresh one via the gear menu → **Change token…**.

## Claude Code

Reads your local Claude Code session transcripts (`~/.claude/projects/**/*.jsonl`)
— the same technique the open-source `ccusage` tool uses. Zero config: no
auth, no tokens, nothing to paste. Costs are estimated from token counts using
Anthropic's published per-model pricing.

For org-wide billing instead of just this Mac's usage, set an Anthropic
**Admin API key** (`sk-ant-admin…`) via the gear menu → **Claude** → **Set
Admin API key…**.

### What it shows

- Today's and this month's estimated spend
- Token totals
- Per-model breakdown

Both providers auto-refresh (Cursor every 10 minutes, Claude every 10
minutes); refresh manually with the ↻ button.

## Build & run

```bash
cd agent-usage
./Scripts/build_app.sh
open build/AgentUsage.app
```

A menu bar icon appears, cycling between the Cursor and Claude brand marks.

## Distributing to your team

The app is **signed with a Developer ID and notarized by Apple** — it opens on
any Mac with zero Gatekeeper warnings, no `xattr`, no right-click workaround.

Rebuild the signed + notarized zip any time with:

```bash
DEVELOPER_ID="Developer ID Application: Itay Shaked (J42P4FD379)" \
NOTARY_PROFILE=CURSORBAR_NOTARY \
./Scripts/make_dist.sh
```

`NOTARY_PROFILE` refers to credentials stored once via `notarytool
store-credentials` (see `xcrun notarytool store-credentials --help`). Output:
`dist/AgentUsage.zip`.

### Option A — plain zip

Share `dist/AgentUsage.zip`. Teammates unzip and drag **AgentUsage** to
`/Applications`, then double-click to open — that's it.

Once running, it works with **zero config**: Cursor auto mode reads each
user's own signed-in Cursor app, and Claude reads their own local logs — no
tokens to share.

### Option B — Homebrew (recommended)

Via engineers already have Homebrew installed (it's step 1 of the
[`via-setup`](https://git.ridewithvia.dev/arch/via-setup) onboarding), so a
custom tap gives a one-line install and easy updates. This repo hosts its own
Cask at `Casks/agentusage.rb`, backed by GitHub Releases.

**Teammates install with:**
```bash
brew tap itayshaked/agent-usage https://github.com/itayshaked/agent-usage.git
brew install --cask agentusage
```

**Updates:**
```bash
brew update && brew upgrade --cask agentusage
```

**Shipping a new version (maintainer):** bump the app, run
`./Scripts/cut_release.sh <new-version>` — builds + signs + notarizes, creates
a GitHub release with the zip attached, and prints the `version`/`sha256` to
paste into `Casks/agentusage.rb`. Commit and push.

## Notes

- No dock icon (`LSUIElement`), menu bar only.
- Cursor token / Claude Admin key live in Keychain (service
  `com.local.agentusage`), never on disk in plaintext.
- Requires macOS 13+.
