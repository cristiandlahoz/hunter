# Hunter

A native macOS energy ledger that shows what happened **since you unplugged** and helps identify likely battery drains.

Hunter is deliberately not another circular battery gauge. It joins the current charge session, live whole-system power, battery health, and a dense application activity ledger in one local-first interface.

## What works

- Current unplugged-session start, duration, charge used, and average drain rate
- Full charge timeline reconstructed from the macOS power log
- Live whole-system watts from `AppleSmartBattery`, retained through the session
- Application Energy Impact sampled every 30 seconds and charted over time
- Per-application observed share, estimated charge equivalent, active time, average impact, and peak impact
- Explicit session-coverage reporting so estimates never imply data existed before monitoring began
- Battery capacity, cycles, and temperature
- Menu-bar summary and full desktop window
- Local development-server discovery with port, project, framework, branch, uptime, and memory
- Vaadin project recognition plus one-click local URLs, server stop controls, and ngrok tunnel start, open, copy, and stop controls
- Zebra-striped server ledgers, process-tree memory totals, and configurable per-server memory alerts (2 GB by default)
- Automatic ngrok installation through Homebrew—or an app-managed download when Homebrew is unavailable—when a tunnel is requested and the dependency is missing
- Optional ChatGPT Codex session and weekly usage limits
- Optional low-battery and full-charge notifications
- Bounded ten-day local history under Application Support

> macOS does not expose trustworthy historical per-app watt-hours. Hunter uses Apple’s relative Energy Impact for application attribution, labels it as an estimate, and keeps measured system power separate.

## Requirements

- macOS 13 or newer
- Apple Silicon is the initial supported target
- Xcode command-line tools for source builds

## Build

```bash
swift test
./scripts/build-app.sh
open dist/Hunter.app
```

To install locally:

```bash
cp -R dist/Hunter.app /Applications/
```

The local build is ad-hoc signed. Distributed releases will require Developer ID signing and notarization.

## Data sources

Hunter executes fixed absolute-path macOS utilities without a shell:

| Data | Source |
| --- | --- |
| Charge, source, remaining time | `pmset -g batt` |
| Charge-session history | `pmset -g log` |
| Watts, cycles, capacity, temperature | `ioreg -rn AppleSmartBattery` |
| Application paths and memory | `ps -axo ...` |
| Local development servers | `lsof -iTCP` plus process working directories and project manifests |
| ngrok tunnels | Local ngrok agent API at `127.0.0.1:4040` |
| Relative application Energy Impact | `top -l 2 -stats ...` |
| Optional Codex usage limits | OpenAI OAuth and `chatgpt.com/backend-api/codex/usage` |

Battery, process, and local-server observations never leave the Mac. Hunter contains no analytics or account system. If you request a tunnel without ngrok installed, Hunter can invoke your local Homebrew executable or download the official ngrok binary into its Application Support folder. If you open an ngrok tunnel, your installed ngrok agent handles its public traffic and credentials. If you connect ChatGPT, the app stores the OAuth credential in macOS Keychain and sends it only to OpenAI to refresh the credential and fetch Codex usage limits.

## Design

The interface adapts the calm density of [Actual Budget](https://actualbudget.org/) to an energy ledger: dark navigation, a light working sheet, compact ruled tables, precise figures, and restrained violet selection.

The macOS data-source approach was informed by the MIT-licensed [Battery Hog](https://github.com/luke-fairbanks/BatteryHog). Hunter is a separate native SwiftUI implementation.

## License

MIT
