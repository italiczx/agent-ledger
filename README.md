<p align="center">
  <img src="Resources/AppIcon-1024.png" alt="Agent Ledger icon" width="128">
</p>

# Agent Ledger

Native macOS menu bar app for the Codex and Cursor usage you have left.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://www.swift.org/)

Agent Ledger reads the quota already attached to your Codex and Cursor sign-in and keeps it in the menu bar. Open the panel for the current window, a more detailed split, local history, and settings. Either tool can be hidden if you only use one of them.

## Features

- Menu bar percents for the tools you turn on, as remaining or used.
- **Summary** shows the live Codex credit or rate window and Cursor's included usage for the current period.
- **Detail** adds extra Codex pools, Cursor Auto and API usage, pace, on-demand limit, and local history.
- **Settings** controls which tools appear, how often they refresh, notifications, and launch at login.
- A notification the first time a visible window reaches 20% left, and again at 5%, once per reset.
- Local trend of those percents, stored only on this Mac.

Local history comes from Codex session logs and Cursor's edit database. It is a record of work on this Mac, separate from the billing window.

## Requirements

- macOS 14 or later
- [Swift 6](https://www.swift.org/install/) (Xcode 16 or later provides it)
- Codex, Cursor, or both, already signed in on this Mac

Codex sign-in is the session from `codex login`. Cursor sign-in is the session in the Cursor app.

## Install

Clone the repository, then build the menu bar app:

```sh
./scripts/build-app.sh
open dist/AgentLedger.app
```

The script builds a release binary, wraps it in `dist/AgentLedger.app`, adds the icon from `Resources/AppIcon-1024.png`, and ad-hoc signs the bundle. The app runs as a menu bar item and does not show a Dock icon.

macOS may refuse the first launch because the signature is ad-hoc. Right-click `dist/AgentLedger.app`, choose **Open**, and confirm. For daily use, move that app to `/Applications` before turning on **Launch at login**.

`dist/` is a build product and is not part of the repository.

## Usage

Click the menu bar item. The label looks like `Cx 72%  Cu 93%`: Codex, then Cursor, as the percent still left. **Settings** can show percent used instead, or turn the numbers off so the item reads `Ledger`. A tool that is hidden is left out. `!` means that tool is signed out, or the last refresh failed and there is no saved quota to keep showing.

The panel has three tabs.

| Tab | Contents |
| --- | --- |
| Summary | Plan, amount left, meter, and reset for each visible tool. **Copy summary** puts the same reading on the clipboard. |
| Detail | Further quota splits and pace, then local history for 7, 30, or 90 days. The range is remembered. |
| Settings | Which tools to show, refresh, menu bar format, alerts, and login. |

Pace stays quiet until enough of the window has passed to estimate a burn rate. When Codex pace is based on a credit limit with no published window length, the line says it assumes a monthly window.

### Settings

| Setting | Default | Effect |
| --- | --- | --- |
| Show Codex | On | Menu bar, both tabs, history, alerts, and copied text. |
| Show Cursor | On | Same, for Cursor. |
| Refresh | 5 min | Also 1, 15, 30, or 60 minutes. |
| Menu bar | Remaining | Remaining, Used, or Off. |
| Notify at 20% and 5% left | On | One alert per threshold for each reset. macOS asks for notification permission the first time a threshold is crossed. |
| Refresh after sleep | On | Refresh when the Mac wakes. Off waits for the normal interval. |
| Launch at login | Off | Available from the built app. `swift run` cannot register a login item. |

### Check quota from the terminal

```sh
swift run AgentLedger --dump
```

This prints the current quota and the last 7 days of local history. It does not print tokens.

## Where the numbers come from

| Source | Used for |
| --- | --- |
| `GET https://chatgpt.com/backend-api/wham/usage` with `~/.codex/auth.json` | Codex credits and rate windows |
| `codex app-server` `account/rateLimits/read` | The same quota when the HTTP login is rejected |
| `~/.codex/sessions/**/*.jsonl` | Codex tokens, models, and projects |
| Keychain item `cursor-access-token`, or `cursorAuth/accessToken` in Cursor's `state.vscdb` | Cursor sign-in |
| `GetCurrentPeriodUsage`, `GetPlanInfo`, and `GetHardLimit` on `api2.cursor.sh` | Cursor included usage for the current period |
| `~/.cursor/ai-tracking/ai-code-tracking.db` | Local Cursor edit counts |

Codex and Cursor do not publish these personal-usage endpoints as a stable API. When a response shape changes, that card shows an error and the last good quota stays on screen.

## Privacy

Agent Ledger uses the Codex and Cursor sign-in already on this Mac and asks those services for your quota. Tokens stay in memory for that request. They are not written into Agent Ledger's files, logs, or anywhere else.

The only thing the app saves is a local trend of percents, in `~/Library/Application Support/AgentLedger/trend.json`. Samples are percents and timestamps. They do not include tokens, account ids, or email addresses.

Agent Ledger has no account of its own, sends no telemetry, and includes no third-party SDK.

The first time it reads Cursor's login, macOS may ask for permission to use the `cursor-access-token` keychain item. Allow it once.

## Development

The project is a Swift package. There is no Xcode project.

```sh
swift test
swift run
swift run AgentLedger --dump
```

`swift test` runs the Swift Testing suite in `Tests/AgentLedgerCoreTests`. `swift run` is enough to try the interface. That process can also appear in the Dock, and **Launch at login** stays disabled.

```
Sources/AgentLedger/           Menu bar app
Sources/AgentLedgerCore/       Quota readers, models, and formatting
Tests/AgentLedgerCoreTests/    Parser and formatting tests
Resources/AppIcon-1024.png     Icon source
scripts/build-app.sh           Release .app bundle
scripts/Info.plist             Bundle id app.agentledger.AgentLedger, agent app
```

## Contributing

Issues and pull requests are welcome. Run `swift test` before opening a pull request.

Do not include auth files, access tokens, keychain dumps, or quota responses that contain an email address or account id. A redacted fixture is enough to show a parser change.

## License

No license file is in this repository yet. Until a `LICENSE` file is added, all rights are reserved and the code is not cleared for reuse.
