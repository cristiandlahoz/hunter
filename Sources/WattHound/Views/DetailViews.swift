import Charts
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var store: EnergyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(
                    title: "Applications",
                    subtitle: "Current activity ranked by macOS Energy Impact"
                ) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.refreshApplications() }
                    }
                    .buttonStyle(.bordered)
                }
                Sheet { ApplicationLedger(applications: store.applications) }
                Text("Energy Impact is Apple’s relative activity score, not a measurement of per-app watts. WattHound samples it over time for session attribution.")
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
    @State private var selectedDate: Date?

    private var sessionSamples: [PowerSample] { store.session?.samples ?? [] }
    private var selectedSample: PowerSample? {
        guard let selectedDate else { return nil }
        return sessionSamples.min {
            abs($0.capturedAt.timeIntervalSince(selectedDate)) < abs($1.capturedAt.timeIntervalSince(selectedDate))
        }
    }
    private var measuredPowerSamples: [PowerSample] { sessionSamples.filter { $0.watts != nil } }
    private var topAttributions: [AppAttribution] { Array(store.sessionAttribution.prefix(12)) }
    private var topIDs: Set<String> {
        Set(topAttributions.filter { !$0.executablePath.isEmpty }.prefix(5).map(\.id))
    }
    private var appSeries: [AppSeriesPoint] {
        store.sessionActivityFrames.flatMap { frame in
            frame.applications.compactMap { app in
                guard topIDs.contains(app.id) else { return nil }
                return AppSeriesPoint(date: frame.capturedAt, appID: app.id, name: app.name, impact: app.relativeImpact)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(
                    title: "Since last charge",
                    subtitle: sessionSubtitle
                )

                coverageNotice

                Sheet {
                    VStack(spacing: 0) {
                        timelineHeader
                        Divider().overlay(WattColors.rule)
                        chargeChart
                            .frame(height: 230)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                        Divider().overlay(WattColors.rule)
                        powerChart
                            .frame(height: 112)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Application activity over time")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WattColors.ink)
                    Text("macOS Energy Impact sampled every 30 seconds")
                        .font(.system(size: 11))
                        .foregroundStyle(WattColors.secondary)
                    Spacer()
                }
                .padding(.top, 8)

                Sheet {
                    VStack(spacing: 0) {
                        if appSeries.isEmpty {
                            emptyActivity
                        } else {
                            appActivityChart
                                .frame(height: 220)
                                .padding(18)
                        }
                        Divider().overlay(WattColors.rule)
                        AttributionLedger(attributions: topAttributions)
                    }
                }

                Text("Application percentages are estimates derived from Apple’s relative Energy Impact samples. Whole-system watts and battery percentage are measured; macOS does not expose exact historical watt-hours per application.")
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(22)
        }
        .background(WattColors.workspace)
    }

    private var sessionSubtitle: String {
        guard let session = store.session else { return "Connect and unplug your Mac to begin a battery session" }
        return "Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) at \(session.startPercentage)% · \(session.percentageDrop)% used"
    }

    private var coverageNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: store.activityCoverage >= 0.95 ? "checkmark.circle.fill" : "scope")
                .foregroundStyle(store.activityCoverage >= 0.95 ? WattColors.energy : WattColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activityCoverage >= 0.95 ? "Full application coverage" : "Application attribution is still building")
                    .font(.system(size: 12, weight: .semibold))
                Text(coverageText)
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
            }
            Spacer()
            Text("\(Int((store.activityCoverage * 100).rounded()))%")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WattColors.ink)
                .tabularMeasurement()
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var coverageText: String {
        guard let first = store.sessionActivityFrames.first else {
            return "Precise app estimates begin with the next 30-second sample; earlier use cannot be reconstructed by macOS."
        }
        return "App activity recorded from \(first.capturedAt.formatted(date: .omitted, time: .shortened)); unsampled gaps are excluded from attribution."
    }

    private var timelineHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Battery and system draw")
                    .font(.system(size: 15, weight: .semibold))
                Text("Measured from AppleSmartBattery")
                    .font(.system(size: 11))
                    .foregroundStyle(WattColors.secondary)
            }
            Spacer()
            if let session = store.session {
                Text("\(session.currentPercentage)% remaining")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WattColors.violet)
                    .tabularMeasurement()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    @ViewBuilder
    private var chargeChart: some View {
        if sessionSamples.count < 2 {
            emptyChart("Waiting for battery history", symbol: "battery.75percent")
        } else {
            let minimum = sessionSamples.map(\.percentage).min() ?? 0
            let lowerBound = max(0, (minimum / 10 * 10) - 10)
            Chart(sessionSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.capturedAt),
                    yStart: .value("Visible baseline", lowerBound),
                    yEnd: .value("Charge", sample.percentage)
                )
                .foregroundStyle(WattColors.violet.opacity(0.1))
                .interpolationMethod(.stepEnd)
                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Charge", sample.percentage)
                )
                .foregroundStyle(WattColors.violet)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.stepEnd)
                if let selectedSample {
                    RuleMark(x: .value("Selected time", selectedSample.capturedAt))
                        .foregroundStyle(WattColors.ink.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedSample.capturedAt.formatted(date: .omitted, time: .shortened))
                                Text("\(selectedSample.percentage)%" + (selectedSample.watts.map { String(format: " · %.1f W", $0) } ?? ""))
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(WattColors.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        }
                }
            }
            .chartYScale(domain: lowerBound...100)
            .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 50))
            .chartYAxisLabel("Charge")
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plot = geometry[proxy.plotAreaFrame]
                                selectedDate = proxy.value(atX: location.x - plot.origin.x, as: Date.self)
                            case .ended:
                                selectedDate = nil
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var powerChart: some View {
        if measuredPowerSamples.count < 2 {
            emptyChart("Live watts appear while WattHound is running", symbol: "bolt")
        } else {
            Chart(measuredPowerSamples) { sample in
                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Watts", sample.watts ?? 0)
                )
                .foregroundStyle(WattColors.energy)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
                PointMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Watts", sample.watts ?? 0)
                )
                .foregroundStyle(WattColors.energy)
                .symbolSize(8)
                if let selectedSample {
                    RuleMark(x: .value("Selected time", selectedSample.capturedAt))
                        .foregroundStyle(WattColors.ink.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 50))
            .chartYAxisLabel("Watts")
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .chartXAxis(.hidden)
        }
    }

    @ViewBuilder
    private var appActivityChart: some View {
        Chart(appSeries) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value("Energy Impact", point.impact),
                series: .value("Application", point.name)
            )
            .foregroundStyle(by: .value("Application", point.name))
            .lineStyle(StrokeStyle(lineWidth: 1.8))
        }
        .chartForegroundStyleScale(range: [WattColors.violet, WattColors.energy, WattColors.warning, .blue, .pink])
        .chartLegend(position: .top, alignment: .leading, spacing: 12)
        .chartYAxisLabel("Impact")
        .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 50))
    }

    private var emptyActivity: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 24))
                .foregroundStyle(WattColors.violet)
            Text("Collecting the first application sample")
                .font(.system(size: 13, weight: .medium))
            Text("Leave WattHound running to build precise session attribution.")
                .font(.system(size: 11))
                .foregroundStyle(WattColors.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func emptyChart(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12))
            .foregroundStyle(WattColors.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppSeriesPoint: Identifiable {
    var id: String { appID + String(date.timeIntervalSince1970) }
    let date: Date
    let appID: String
    let name: String
    let impact: Double
}

private struct AttributionLedger: View {
    let attributions: [AppAttribution]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Application").frame(maxWidth: .infinity, alignment: .leading)
                Text("Observed share").frame(width: 116, alignment: .trailing)
                Text("Est. battery").frame(width: 96, alignment: .trailing)
                Text("Active").frame(width: 82, alignment: .trailing)
                Text("Avg / peak").frame(width: 100, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WattColors.secondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Color(red: 247/255, green: 249/255, blue: 251/255))
            Divider().overlay(WattColors.rule)

            if attributions.isEmpty {
                Text("No application attribution is available for this session yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(WattColors.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(Array(attributions.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        AppIcon(path: item.executablePath)
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WattColors.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.observedShare.formatted(.percent.precision(.fractionLength(1))))
                            .frame(width: 116, alignment: .trailing)
                        Text(String(format: "%.2f%%", item.equivalentCharge))
                            .frame(width: 96, alignment: .trailing)
                        Text(Formatters.duration(item.activeDuration))
                            .frame(width: 82, alignment: .trailing)
                        Text(item.executablePath.isEmpty ? "—" : String(format: "%.1f / %.1f", item.averageImpact, item.peakImpact))
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(WattColors.secondary)
                    .tabularMeasurement()
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(index.isMultiple(of: 2) ? Color.white : WattColors.workspace.opacity(0.34))
                    .overlay(alignment: .bottom) { Divider().overlay(WattColors.rule.opacity(0.7)) }
                }
            }
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
