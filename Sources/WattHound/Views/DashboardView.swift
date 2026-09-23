import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: EnergyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pageHeader

                if let errorMessage = store.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Sheet {
                    VStack(spacing: 0) {
                        chartHeader
                        Divider().overlay(WattColors.rule)
                        sessionChart
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .frame(height: 230)
                        Divider().overlay(WattColors.rule)
                        summaryStrip
                    }
                }

                HStack {
                    Text("Likely contributors")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WattColors.ink)
                    Text("Estimated from current CPU and memory activity")
                        .font(.system(size: 11))
                        .foregroundStyle(WattColors.secondary)
                    Spacer()
                }
                .padding(.top, 8)

                Sheet {
                    ApplicationLedger(applications: store.applications, limit: 8)
                }
            }
            .padding(22)
        }
        .background(WattColors.workspace)
    }

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Current session")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(WattColors.ink)
                HStack(spacing: 7) {
                    StatusDot(color: store.snapshot.isOnAC ? WattColors.violet : WattColors.energy)
                    Text(sessionSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(WattColors.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Label(store.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var chartHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.snapshot.isOnAC ? "Connected to power" : "Battery since unplugged")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WattColors.ink)
                Text(chartRangeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
            }
            Spacer()
            Text("\(store.snapshot.percentage)%")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(WattColors.violet)
                .tabularMeasurement()
        }
        .padding(.horizontal, 18)
        .frame(height: 67)
    }

    @ViewBuilder
    private var sessionChart: some View {
        let chartSamples = store.session?.samples.isEmpty == false
            ? store.session!.samples
            : Array(store.recentSamples.suffix(120))
        if chartSamples.count < 2 {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 24))
                    .foregroundStyle(WattColors.violet)
                Text("Building this session’s timeline")
                    .font(.system(size: 13, weight: .medium))
                Text("WattHound will add a point as the battery changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let minimum = chartSamples.map(\.percentage).min() ?? 0
            let lowerBound = max(0, (minimum / 10 * 10) - 10)
            Chart(chartSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.capturedAt),
                    yStart: .value("Visible baseline", lowerBound),
                    yEnd: .value("Charge", sample.percentage)
                )
                .foregroundStyle(WattColors.violet.opacity(0.11))
                .interpolationMethod(.stepEnd)

                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Charge", sample.percentage)
                )
                .foregroundStyle(WattColors.violet)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: lowerBound...100)
            .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 26))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(WattColors.rule)
                    AxisValueLabel {
                        if let percentage = value.as(Int.self) { Text("\(percentage)%") }
                    }
                    .foregroundStyle(WattColors.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(WattColors.rule.opacity(0.55))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(WattColors.secondary)
                }
            }
            .accessibilityLabel("Battery charge timeline")
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            SummaryCell(label: "SESSION", value: sessionDuration, detail: sessionStart)
            Divider().frame(height: 54).overlay(WattColors.rule)
            SummaryCell(label: "CHARGE USED", value: chargeUsed, detail: "Since unplugged")
            Divider().frame(height: 54).overlay(WattColors.rule)
            SummaryCell(label: "AVG. DRAIN", value: drainRate, detail: "Percentage per hour")
            Divider().frame(height: 54).overlay(WattColors.rule)
            SummaryCell(label: "POWER NOW", value: powerNow, detail: "Whole-system draw")
        }
        .frame(height: 82)
    }

    private var sessionSubtitle: String {
        if store.snapshot.isOnAC { return store.snapshot.isCharging ? "Charging now" : "Battery held on adapter" }
        return "On battery · \(Formatters.time(store.snapshot.timeRemainingMinutes)) remaining"
    }

    private var chartRangeLabel: String {
        guard let session = store.session else { return "Waiting for an unplugged session" }
        return "Started \(session.startedAt.formatted(date: .omitted, time: .shortened)) at \(session.startPercentage)%"
    }

    private var sessionDuration: String {
        store.session.map { Formatters.duration($0.duration) } ?? "—"
    }

    private var sessionStart: String {
        store.session.map { "From \($0.startPercentage)%" } ?? "On power adapter"
    }

    private var chargeUsed: String {
        store.session.map { "\($0.percentageDrop)%" } ?? "—"
    }

    private var drainRate: String {
        store.session?.drainPerHour.map { String(format: "%.1f%%", $0) } ?? "—"
    }

    private var powerNow: String {
        store.snapshot.watts.map { String(format: "%.1f W", $0) } ?? "—"
    }
}

private struct SummaryCell: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(WattColors.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WattColors.ink)
                .tabularMeasurement()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(WattColors.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(WattColors.critical)
        .padding(12)
        .background(Color(red: 1, green: 0.94, blue: 0.94), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
