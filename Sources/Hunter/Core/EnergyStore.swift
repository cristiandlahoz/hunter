import Foundation
import SwiftUI

@MainActor
final class EnergyStore: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.empty
    @Published private(set) var applications: [AppImpact] = []
    @Published private(set) var samples: [PowerSample] = []
    @Published private(set) var activityFrames: [AppActivityFrame] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @AppStorage("monitoringEnabled") var monitoringEnabled = true

    private let probe = SystemProbe()
    private let historyStore = HistoryStore()
    private let notificationService = NotificationService()
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

    var sessionActivityFrames: [AppActivityFrame] {
        guard let session else { return [] }
        return activityFrames.filter { $0.capturedAt >= session.startedAt && !$0.applications.isEmpty }
    }

    var activityCoverage: Double {
        guard let session else { return 0 }
        let frames = sessionActivityFrames.sorted { $0.capturedAt < $1.capturedAt }
        guard !frames.isEmpty else { return 0 }
        let observed = frames.enumerated().reduce(0.0) { total, pair in
            let index = pair.offset
            let frame = pair.element
            let next = index + 1 < frames.count ? frames[index + 1].capturedAt : Date()
            return total + max(0, min(120, next.timeIntervalSince(frame.capturedAt)))
        }
        return min(1, observed / max(session.duration, 1))
    }

    var sessionAttribution: [AppAttribution] {
        guard let session else { return [] }
        return AttributionCalculator.calculate(
            session: session,
            frames: sessionActivityFrames
        )
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
            errorMessage = "Hunter couldn’t read the current battery state. Try refreshing."
            return
        }
        let previousSnapshot = snapshot
        snapshot = newSnapshot
        errorMessage = nil
        appendSample(from: newSnapshot)
        await notificationService.evaluate(
            previous: previousSnapshot,
            current: newSnapshot,
            enabled: UserDefaults.standard.bool(forKey: "notificationsEnabled")
        )

        processRefreshCounter += 1
        if applications.isEmpty || processRefreshCounter >= 2 {
            let activity = await probe.applicationImpact()
            applications = activity.applications
            appendActivity(activity, battery: newSnapshot)
            processRefreshCounter = 0
        }
    }

    func refreshApplications() async {
        let activity = await probe.applicationImpact()
        applications = activity.applications
        appendActivity(activity, battery: snapshot)
    }

    func enableNotifications() async -> Bool {
        await notificationService.requestAuthorization()
    }

    private func bootstrap() async {
        async let local = historyStore.load()
        async let activity = historyStore.loadActivity()
        async let system = probe.systemPowerHistory()
        samples = Self.merge(system: await system, local: await local)
        activityFrames = (await activity).sorted { $0.capturedAt < $1.capturedAt }
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

    private func appendActivity(_ activity: ProcessActivitySnapshot, battery: BatterySnapshot) {
        let frame = AppActivityFrame(
            capturedAt: activity.capturedAt,
            batteryPercentage: battery.percentage,
            systemWatts: battery.watts,
            totalSystemImpact: activity.totalSystemImpact,
            applications: Array(activity.applications.prefix(15))
        )
        activityFrames.append(frame)
        let cutoff = Date().addingTimeInterval(-10 * 86_400)
        activityFrames.removeAll { $0.capturedAt < cutoff }
        Task { await historyStore.appendActivity(frame) }
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
