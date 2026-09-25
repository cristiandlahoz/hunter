# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS

## Stack

Native Swift and SwiftUI, delegated by the user with performance and low resource use as primary constraints.

## Users

MacBook users who want to understand a battery session without reconstructing it from several macOS utilities. They open Hunter while unplugged to answer when the session began, how quickly charge is falling, and which applications are likely contributing.

## Product Purpose

Hunter tracks battery state, discharge, charge sessions, health, and application activity locally. Success means the current unplugged session is immediately understandable and the user can identify likely drains without granting broad permissions or uploading telemetry.

## Positioning

Hunter treats energy as a ledger: one continuous session timeline joined to a dense, inspectable process list. It distinguishes measured system power from estimated per-app impact rather than presenting estimates as per-app watts.

## Operating Context

The app runs quietly in the macOS menu bar and opens into a desktop window for investigation. It reads built-in macOS power and process data and keeps a bounded local sample history.

## Capabilities and Constraints

- Native macOS application, initially targeting Apple Silicon and macOS 13 or newer.
- Current charge, power source, estimated time remaining, measured battery watts, health, cycles, and temperature.
- Current unplugged-session start, duration, percentage drop, and average drain rate.
- Charge history reconstructed from macOS power logs and continued with local samples.
- Relative application-impact ranking and session attribution based on sampled macOS Energy Impact; macOS does not expose trustworthy historical per-app watt-hours.
- Explicit attribution coverage, observed share, estimated charge equivalent, active time, average impact, and peak impact for each sampled application.
- Menu-bar status and desktop dashboard.
- Local development-server discovery with Vaadin recognition, project and branch context, resource use, and direct browser links.
- Start, inspect, copy, open, and stop public tunnels through ngrok, with automatic Homebrew or app-managed installation when the binary is missing.
- Configurable per-server process-tree memory alerts, defaulting to 2 GB.
- Optional ChatGPT Codex usage limits, authenticated directly with OpenAI and stored in macOS Keychain.
- No Hunter account, analytics, Electron runtime, or mandatory administrator privileges.

## Brand Commitments

The product name is Hunter. Its interface should inherit the useful qualities of Actual Budget: a dark, highly legible sidebar; light data workspace; compact tables; direct labels; and restrained violet selection. It must remain recognizably native to macOS rather than copying a web application literally.

## Evidence on Hand

- Actual Budget source and local reference checkout: `/Users/cigdelahoz/ghq/github.com/cristiandlahoz/actual`.
- Battery Hog's public MIT-licensed implementation demonstrates relevant macOS sources including `pmset`, `ioreg`, `system_profiler`, and `ps`.
- No performance benchmarks or per-app watt measurements exist and none should be fabricated.

## Product Principles

- Show the current battery session first.
- Keep measured facts distinct from estimates.
- Spend less energy monitoring than the problems being diagnosed.
- Keep all observations local and inspectable.
- Prefer dense, calm information over decorative dashboards.

## Accessibility & Inclusion

Support keyboard navigation, VoiceOver labels, Reduce Motion, increased contrast, and system text rendering. Do not encode charging state or severity by color alone.
