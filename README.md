# CursorUsageBar

A native macOS menu bar app that shows your Cursor usage (requests, spend, and a
per-model breakdown) right from the top bar.

It authenticates the same way the Cursor web dashboard does — with your
`WorkosCursorSessionToken` browser cookie, stored securely in your macOS
Keychain. It only ever talks to `cursor.com`.

> These endpoints are **unofficial** (reverse-engineered from the dashboard) and
> may change or break without notice.

## Build & run

```bash
cd CursorUsageBar
./Scripts/build_app.sh
open build/CursorUsageBar.app
```

A `⌖` icon appears in your menu bar. Click it and paste your token.

## Get your session token

1. Open <https://cursor.com/dashboard/usage> while logged in.
2. Open DevTools (⌥⌘I) → **Application** → **Cookies** → `https://cursor.com`.
3. Copy the **value** of `WorkosCursorSessionToken` (looks like
   `user_01…%3A%3AeyJ…`).
4. Paste it into the app and hit **Save**.

The token is a JWT with an expiry; when it lapses you'll see an auth error and
just paste a fresh one via the gear menu → **Change token…**.

## What it shows

- Account email and plan (membership type)
- Current billing cycle
- Requests used / limit (with a progress bar)
- Spend this cycle (from aggregated usage events)
- Per-model breakdown (spend or request count)

Auto-refreshes every 10 minutes; refresh manually with the ↻ button.

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
`dist/CursorUsageBar.zip`.

### Option A — plain zip

Share `dist/CursorUsageBar.zip`. Teammates unzip and drag **CursorUsageBar** to
`/Applications`, then double-click to open — that's it.

Once running, it works with **zero config** because Auto mode reads each user's
own signed-in Cursor app — no tokens to share.

### Option B — Homebrew (recommended)

Via engineers already have Homebrew installed (it's step 1 of the
[`via-setup`](https://git.ridewithvia.dev/arch/via-setup) onboarding), so a
custom tap gives a one-line install and easy updates. This repo hosts its own
Cask at `Casks/cursorusagebar.rb`, backed by GitHub Releases.

**Teammates install with:**
```bash
brew tap itayshaked/cursor-usage-bar https://github.com/itayshaked/cursor-usage-bar.git
brew install --cask cursorusagebar
```

**Updates:**
```bash
brew update && brew upgrade --cask cursorusagebar
```

**Shipping a new version (maintainer):** bump the app, run
`./Scripts/cut_release.sh <new-version>` — builds + signs + notarizes, creates
a GitHub release with the zip attached, and prints the `version`/`sha256` to
paste into `Casks/cursorusagebar.rb`. Commit and push.

## Notes

- No dock icon (`LSUIElement`), menu bar only.
- Token lives in Keychain (service `com.local.cursorusagebar`), never on disk in
  plaintext.
- Requires macOS 13+.
