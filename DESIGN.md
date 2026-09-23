# WattHound Design System

## Direction contract

**THESIS** — Battery investigation behaves like reconciling a ledger, not admiring a telemetry dashboard. The interface refuses rings, glowing gauges, and floating metric-card grids.

**OWN-WORLD** — Ink-navy navigation, cool paper workspace, thin ledger rules, violet selection, and chartreuse energy markers. Controls are compact, squared, and native; tabular figures align precisely.

**STORY** — The user sees when this unplugged session began, reads its loss and rate across one timeline, then follows the ranked application ledger to likely contributors.

**FIRST VIEWPORT** — A fixed 224-point sidebar frames a wide session sheet: title and source state above one uninterrupted chart, a narrow summary strip, then the process ledger. Refresh lives in the toolbar.

**FORM** — Native macOS split workspace, adapted from Actual Budget’s dense navigation and budgeting-table grammar for an energy ledger.

## Visual language

WattHound uses a restrained palette. The sidebar is a continuous deep navy field. The workspace is a cool, nearly white paper surface with white table rows. Violet marks selection and active controls; chartreuse marks live battery energy; amber and red are reserved for actionable warning states.

Do not use decorative gradients, glass, neon glow, circular progress gauges, or collections of interchangeable metric cards. Hierarchy comes from region, typography, rules, and aligned data.

## Tokens

- Sidebar: `#102F49`
- Sidebar hover: `#183F5E`
- Sidebar text: `#DCEAF3`
- Sidebar muted: `#86A7BC`
- Workspace: `#EEF2F5`
- Sheet: `#FFFFFF`
- Primary text: `#272630`
- Secondary text: `#607083`
- Rule: `#D8E0E7`
- Violet: `#8B3DFF`
- Violet wash: `#EEE5FF`
- Energy: `#78B833`
- Warning: `#C47A16`
- Critical: `#C74646`

Use 6-, 10-, and 14-point radii according to control scale. Major sheets use a 10-point radius and one soft, low-opacity shadow; dense rows use rules, not cards.

## Typography

Use San Francisco through SwiftUI system styles. Titles are semibold rather than oversized. Measurements use monospaced digits, not a monospaced typeface. Sidebar and table labels remain compact and readable.

## Layout

The sidebar is 224 points wide and never becomes a floating card. Content has a minimum useful width of 760 points. The chart owns horizontal space. Summary values form a single ruled strip. The application list is a ledger with stable columns and 36-point rows.

## Interaction

Selection is immediate, with a violet text/icon treatment over a navy hover field. Refresh rotates the symbol once only when work is active and respects Reduce Motion. Every status combines an icon or label with color. Empty and error states remain in the sheet instead of opening modal dialogs.
