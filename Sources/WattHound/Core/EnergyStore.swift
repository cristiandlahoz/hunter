import Foundation
import SwiftUI

@MainActor
final class EnergyStore: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.empty
    @Published private(set) var applications: [AppImpact] = []
    @Published private(set) var samples: [PowerSample] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @AppStorage("monitoringEnabled") var monitoringEnabled = true

    private let probe = SystemProbe()
    private let historyStore = HistoryStore()
    private var refreshTimer: Timer?
    private var processRefreshCounter = 0
    private var lastPersistedAt: Date?

    var session: BatterySession? {
        guard !snapshot.isOnAC else { return nil }
        let ordered = samples.sorted { $0.capturedAt < $1.capturedAt }
        let lastACIndex = ordered.lastIndex(where: { $0.isOnAC })
        let candidates = if let lastACIndex {
            Array(ordered.dropFirst(lastACIndex + 1)).filter { !$0.isOnAC }
        } else {
            ordered.filter { !$0.isOnAC }
        }
        guard let first = candidates.first else {
            return BatterySession(
                startedAt: snapshot.capturedAt,
                startPercentage: snapshot.percentage,
                currentPercentage: snapshot.percentage,
                samples: []
            )
        }
        return BatterySession(
            startedAt: first.capturedAt,
            startPercentage: first.percentage,
            currentPercentage: snapshot.percentage,
            samples: candidates
        )
    }

    var recentSamples: [PowerSample] {
        let cutoff = Date().addingTimeInterval(-24 * 3_600)
        return samples.filter { $0.capturedAt >= cutoff }
    }

    func start() {
        guard refreshTimer == nil else { return }
        Task { await bootstrap() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.monitoringEnabled else { return }
                await self.refresh()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let newSnapshot = await probe.batterySnapshot() else {
            errorMessage = "WattHound couldn’t read the current battery state. Try refreshing."
            return
        }
        snapshot = newSnapshot
        errorMessage = nil
        appendSample(from: newSnapshot)

        processRefreshCounter += 1
        if applications.isEmpty || processRefreshCounter >= 2 {
            applications = await probe.applicationImpact()
            processRefreshCounter = 0
        }
    }

    func refreshApplications() async {
        applications = await probe.applicationImpact()
    }

    private func bootstrap() async {
        let local = await historyStore.load()
        async let system = probe.systemPowerHistory()
        samples = Self.merge(system: await system, local: local)
        await refresh()
    }

    private func appendSample(from snapshot: BatterySnapshot) {
        let sample = PowerSample(
            capturedAt: snapshot.capturedAt,
            percentage: snapshot.percentage,
            watts: snapshot.watts,
            isOnAC: snapshot.isOnAC
        )
        samples.append(sample)
        let cutoff = Date().addingTimeInterval(-10 * 86_400)
        samples.removeAll { $0.capturedAt < cutoff }

        if lastPersistedAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true {
            lastPersistedAt = .now
            let copy = samples
            Task { await historyStore.save(copy) }
        }
    }

    nonisolated static func merge(system: [PowerSample], local: [PowerSample]) -> [PowerSample] {
        (system + local)
            .sorted { $0.capturedAt < $1.capturedAt }
            .reduce(into: []) { result, sample in
                if let last = result.last {
                    let interval = sample.capturedAt.timeIntervalSince(last.capturedAt)
                    if interval < 30,
                       last.percentage == sample.percentage,
                       last.isOnAC == sample.isOnAC { return }
                    if interval < 1_800, abs(last.percentage - sample.percentage) > 25 { return }
                }
                result.append(sample)
            }
    }
}
