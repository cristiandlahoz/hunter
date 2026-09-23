# WattHound

A native macOS energy ledger that shows what happened **since you unplugged** and helps identify likely battery drains.

WattHound is deliberately not another circular battery gauge. It joins the current charge session, live whole-system power, battery health, and a dense application activity ledger in one local-first interface.

## What works

- Current unplugged-session start, duration, charge used, and average drain rate
- Full charge timeline reconstructed from the macOS power log
- Live whole-system watts from `AppleSmartBattery`, retained through the session
- Application Energy Impact sampled every 30 seconds and charted over time
- Per-application observed share, estimated charge equivalent, active time, average impact, and peak impact
- Explicit session-coverage reporting so estimates never imply data existed before monitoring began
- Battery capacity, cycles, and temperature
- Menu-bar summary and full desktop window
- Optional low-battery and full-charge notifications
- Bounded ten-day local history under Application Support

> macOS does not expose trustworthy historical per-app watt-hours. WattHound uses Apple’s relative Energy Impact for application attribution, labels it as an estimate, and keeps measured system power separate.

## Requirements

- macOS 13 or newer
- Apple Silicon is the initial supported target
- Xcode command-line tools for source builds

## Build

```bash
swift test
./scripts/build-app.sh
open dist/WattHound.app
```

To install locally:

```bash
cp -R dist/WattHound.app /Applications/
```

The local build is ad-hoc signed. Distributed releases will require Developer ID signing and notarization.

## Data sources

WattHound executes fixed absolute-path macOS utilities without a shell:

| Data | Source |
| --- | --- |
| Charge, source, remaining time | `pmset -g batt` |
| Charge-session history | `pmset -g log` |
| Watts, cycles, capacity, temperature | `ioreg -rn AppleSmartBattery` |
| Application paths and memory | `ps -axo ...` |
| Relative application Energy Impact | `top -l 2 -stats ...` |

No observations leave the Mac. WattHound contains no analytics or account system.

## Design

The interface adapts the calm density of [Actual Budget](https://actualbudget.org/) to an energy ledger: dark navigation, a light working sheet, compact ruled tables, precise figures, and restrained violet selection.

The macOS data-source approach was informed by the MIT-licensed [Battery Hog](https://github.com/luke-fairbanks/BatteryHog). WattHound is a separate native SwiftUI implementation.

## License

MIT
