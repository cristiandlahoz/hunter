import Foundation

enum AttributionCalculator {
    static func calculate(
        session: BatterySession,
        frames: [AppActivityFrame],
        now: Date = .now
    ) -> [AppAttribution] {
        let ordered = frames.sorted { $0.capturedAt < $1.capturedAt }
        guard !ordered.isEmpty else { return [] }

        struct Accumulator {
            var name = ""
            var path = ""
            var exposure = 0.0
            var activeDuration = 0.0
            var weightedImpact = 0.0
            var peakImpact = 0.0
        }
        var values: [String: Accumulator] = [:]
        var totalExposure = 0.0

        for (index, frame) in ordered.enumerated() {
            let nextDate = index + 1 < ordered.count ? ordered[index + 1].capturedAt : now
            let duration = max(0, min(120, nextDate.timeIntervalSince(frame.capturedAt)))
            guard duration > 0 else { continue }
            totalExposure += frame.totalSystemImpact * duration
            for app in frame.applications {
                var value = values[app.id, default: Accumulator()]
                value.name = app.name
                value.path = app.executablePath
                value.exposure += app.relativeImpact * duration
                value.weightedImpact += app.relativeImpact * duration
                value.peakImpact = max(value.peakImpact, app.relativeImpact)
                if app.relativeImpact >= 0.1 { value.activeDuration += duration }
                values[app.id] = value
            }
        }
        guard totalExposure > 0 else { return [] }

        var result = values.map { id, value in
            let share = min(1, value.exposure / totalExposure)
            return AppAttribution(
                id: id,
                name: value.name,
                executablePath: value.path,
                observedShare: share,
                equivalentCharge: Double(session.percentageDrop) * share,
                activeDuration: value.activeDuration,
                averageImpact: value.activeDuration > 0 ? value.weightedImpact / value.activeDuration : 0,
                peakImpact: value.peakImpact
            )
        }
        let assignedShare = min(1, result.reduce(0) { $0 + $1.observedShare })
        let residual = max(0, 1 - assignedShare)
        if residual >= 0.005 {
            result.append(AppAttribution(
                id: "system-unassigned",
                name: "System & unassigned",
                executablePath: "",
                observedShare: residual,
                equivalentCharge: Double(session.percentageDrop) * residual,
                activeDuration: max(0, now.timeIntervalSince(session.startedAt)),
                averageImpact: 0,
                peakImpact: 0
            ))
        }
        return result.sorted { $0.observedShare > $1.observedShare }
    }
}
