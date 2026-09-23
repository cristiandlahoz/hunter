import Foundation

actor SystemProbe {
    private var cachedHealth: (date: Date, health: Int?, cycles: Int?, temperature: Double?)?

    func batterySnapshot() -> BatterySnapshot? {
        let battery = CommandRunner.run("/usr/bin/pmset", arguments: ["-g", "batt"], timeout: 4)
        let registry = CommandRunner.run("/usr/sbin/ioreg", arguments: ["-rn", "AppleSmartBattery"], timeout: 5)
        guard battery.succeeded else { return nil }

        let percentage = Self.firstInt(#"(\d+)%"#, in: battery.output) ?? 0
        let isOnAC = battery.output.contains("AC Power")
        let status = battery.output.lowercased()
        let isCharging = status.contains("charging") && !status.contains("not charging")
        let remaining = Self.firstMatch(#"(\d+):(\d+)\s+remaining"#, in: battery.output)
        let minutes = remaining.flatMap { match -> Int? in
            guard match.count == 2, let hours = Int(match[0]), let mins = Int(match[1]) else { return nil }
            return hours * 60 + mins
        }

        let amperage = Self.ioInteger("InstantAmperage", in: registry.output)
            ?? Self.ioInteger("Amperage", in: registry.output)
        let voltage = Self.ioInteger("Voltage", in: registry.output)
        let watts: Double? = if let amperage, let voltage {
            abs(Double(amperage)) * Double(voltage) / 1_000_000
        } else {
            nil
        }

        let health = healthValues(registry: registry.output)
        return BatterySnapshot(
            capturedAt: .now,
            percentage: percentage,
            isOnAC: isOnAC,
            isCharging: isCharging,
            timeRemainingMinutes: minutes,
            watts: watts,
            healthPercentage: health.health,
            cycleCount: health.cycles,
            temperatureCelsius: health.temperature
        )
    }

    func applicationImpact() -> [AppImpact] {
        let result = CommandRunner.run(
            "/bin/ps",
            arguments: ["-axo", "pid=,pcpu=,rss=,comm="],
            timeout: 5
        )
        guard result.succeeded else { return [] }

        struct Aggregate {
            var count = 0
            var cpu = 0.0
            var memory: UInt64 = 0
            var path = ""
        }
        var groups: [String: Aggregate] = [:]

        for line in result.output.split(separator: "\n") {
            let fields = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            guard fields.count == 4,
                  Double(fields[1]) != nil,
                  UInt64(fields[2]) != nil else { continue }
            let cpu = Double(fields[1]) ?? 0
            let memory = (UInt64(fields[2]) ?? 0) * 1_024
            let path = String(fields[3])
            guard !path.contains("WattHound"), Self.isUserRelevantProcess(path) else { continue }
            let identity = Self.applicationIdentity(for: path)
            var aggregate = groups[identity.name, default: Aggregate()]
            aggregate.count += 1
            aggregate.cpu += cpu
            aggregate.memory += memory
            if aggregate.path.isEmpty || identity.path.contains(".app/") {
                aggregate.path = identity.path
            }
            groups[identity.name] = aggregate
        }

        return groups.map { name, value in
            let memoryGB = Double(value.memory) / 1_073_741_824
            let score = value.cpu + min(memoryGB * 3, 12)
            return AppImpact(
                id: name + value.path,
                name: name,
                executablePath: value.path,
                processCount: value.count,
                cpuPercentage: value.cpu,
                memoryBytes: value.memory,
                relativeImpact: score
            )
        }
        .filter { $0.cpuPercentage >= 0.1 || $0.memoryBytes >= 50 * 1_048_576 }
        .sorted { $0.relativeImpact > $1.relativeImpact }
        .prefix(40)
        .map { $0 }
    }

    func systemPowerHistory() -> [PowerSample] {
        let result = CommandRunner.run(
            "/usr/bin/pmset",
            arguments: ["-g", "log"],
            timeout: 20,
            keepLine: { $0.contains("Using Batt") || $0.contains("Using AC") }
        )
        guard result.succeeded else { return [] }
        return Self.parsePowerHistory(result.output)
    }

    private func healthValues(registry: String) -> (health: Int?, cycles: Int?, temperature: Double?) {
        if let cachedHealth, Date().timeIntervalSince(cachedHealth.date) < 60 {
            return (cachedHealth.health, cachedHealth.cycles, cachedHealth.temperature)
        }
        let design = Self.ioInteger("DesignCapacity", in: registry)
        let full = Self.ioInteger("NominalChargeCapacity", in: registry)
            ?? Self.ioInteger("AppleRawMaxCapacity", in: registry)
        let computedHealth: Int? = if let design, let full, design > 0 {
            Int((Double(full) / Double(design) * 100).rounded())
        } else {
            nil
        }
        let cycles = Self.ioInteger("CycleCount", in: registry).map(Int.init)
        let temperature = Self.ioInteger("Temperature", in: registry).map { Double($0) / 100 }
        cachedHealth = (.now, computedHealth, cycles, temperature)
        return (computedHealth, cycles, temperature)
    }

    static func parsePowerHistory(_ text: String) -> [PowerSample] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let pattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}).*Using\s+(Batt|AC).*?Charge:\s*(\d+)%?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var samples: [PowerSample] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let dateRange = Range(match.range(at: 1), in: text),
                  let sourceRange = Range(match.range(at: 2), in: text),
                  let percentageRange = Range(match.range(at: 3), in: text),
                  let date = formatter.date(from: String(text[dateRange])),
                  let percentage = Int(text[percentageRange]) else { return }
            samples.append(PowerSample(
                capturedAt: date,
                percentage: percentage,
                watts: nil,
                isOnAC: text[sourceRange] == "AC"
            ))
        }
        return samples
            .sorted { $0.capturedAt < $1.capturedAt }
            .reduce(into: []) { result, sample in
                if let last = result.last {
                    let interval = sample.capturedAt.timeIntervalSince(last.capturedAt)
                    if interval < 30,
                       last.percentage == sample.percentage,
                       last.isOnAC == sample.isOnAC { return }
                    // powerd occasionally emits a truncated `100` as `10`; a battery
                    // cannot physically move by this much inside half an hour.
                    if interval < 1_800, abs(last.percentage - sample.percentage) > 25 { return }
                }
                result.append(sample)
            }
    }

    static func isUserRelevantProcess(_ path: String) -> Bool {
        if path.contains(".app/") { return true }
        if path.hasPrefix("/Users/") || path.hasPrefix("/Applications/")
            || path.hasPrefix("/opt/") || path.hasPrefix("/usr/local/") { return true }
        return !path.hasPrefix("/")
    }

    static func applicationIdentity(for path: String) -> (name: String, path: String) {
        if let appRange = path.range(of: #"/[^/]+\.app/"#, options: .regularExpression) {
            let appPath = String(path[..<appRange.upperBound]).dropLast()
            let name = URL(fileURLWithPath: String(appPath)).deletingPathExtension().lastPathComponent
            return (name, String(appPath))
        }
        let url = URL(fileURLWithPath: path)
        let raw = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        return (raw, path)
    }

    private static func ioInteger(_ key: String, in text: String) -> Int64? {
        guard let raw = firstMatch(#"\""# + NSRegularExpression.escapedPattern(for: key) + #"\"\s*=\s*(-?\d+)"#, in: text)?.first else {
            return nil
        }
        if let signed = Int64(raw) { return signed }
        return UInt64(raw).map { Int64(bitPattern: $0) }
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        firstMatch(pattern, in: text)?.first.flatMap(Int.init)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
