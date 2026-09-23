import Charts
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var store: EnergyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(
                    title: "Applications",
                    subtitle: "Current activity ranked by a relative CPU and memory estimate"
                ) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.refreshApplications() }
                    }
                    .buttonStyle(.bordered)
                }
                Sheet { ApplicationLedger(applications: store.applications) }
                Text("Impact is a comparison aid, not a measurement of per-app watts. macOS does not expose reliable per-app battery power history.")
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(22)
        }
        .background(WattColors.workspace)
    }
}

struct HistoryView: View {
    @ObservedObject var store: EnergyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "History", subtitle: "Battery level and power-source changes from the last 24 hours")
                Sheet {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Last 24 hours")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Label("Battery", systemImage: "circle.fill")
                                .foregroundStyle(WattColors.violet)
                            Label("Adapter", systemImage: "circle.fill")
                                .foregroundStyle(WattColors.energy)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        Divider().overlay(WattColors.rule)
                        historyChart
                            .frame(height: 330)
                            .padding(18)
                    }
                }
            }
            .padding(22)
        }
        .background(WattColors.workspace)
    }

    @ViewBuilder
    private var historyChart: some View {
        if store.recentSamples.count < 2 {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(WattColors.violet)
                Text("No history is available yet")
                    .font(.system(size: 13, weight: .medium))
                Text("Battery samples will appear here while WattHound runs.")
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(store.recentSamples) { sample in
                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Charge", sample.percentage),
                    series: .value("Source", sample.isOnAC ? "Adapter" : "Battery")
                )
                .foregroundStyle(sample.isOnAC ? WattColors.energy : WattColors.violet)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) }
        }
    }
}

struct BatteryView: View {
    @ObservedObject var store: EnergyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "Battery", subtitle: "Capacity, condition, and live electrical measurements")
                Sheet {
                    VStack(spacing: 0) {
                        BatteryRow(label: "Current charge", value: "\(store.snapshot.percentage)%", symbol: "battery.75percent")
                        BatteryRow(label: "Maximum capacity", value: optionalPercent(store.snapshot.healthPercentage), symbol: "heart.text.square")
                        BatteryRow(label: "Cycle count", value: optionalNumber(store.snapshot.cycleCount), symbol: "arrow.triangle.2.circlepath")
                        BatteryRow(label: "Temperature", value: temperature, symbol: "thermometer.medium")
                        BatteryRow(label: "Live power", value: watts, symbol: "bolt.fill", isLast: true)
                    }
                }
            }
            .padding(22)
        }
        .background(WattColors.workspace)
    }

    private func optionalPercent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "Unavailable" }
    private func optionalNumber(_ value: Int?) -> String { value.map(String.init) ?? "Unavailable" }
    private var temperature: String { store.snapshot.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "Unavailable" }
    private var watts: String { store.snapshot.watts.map { String(format: "%.2f W", $0) } ?? "Unavailable" }
}

private struct BatteryRow: View {
    let label: String
    let value: String
    let symbol: String
    var isLast = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(WattColors.violet)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(WattColors.ink)
            Spacer()
            Text(value)
                .foregroundStyle(WattColors.secondary)
                .tabularMeasurement()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 18)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().overlay(WattColors.rule) }
        }
    }
}

struct PageTitle<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(WattColors.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(WattColors.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
