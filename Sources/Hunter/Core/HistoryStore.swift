import Foundation

actor HistoryStore {
    private let fileURL: URL
    private let activityURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hunter", isDirectory: true)
        fileURL = root.appendingPathComponent("power-samples.json")
        activityURL = root.appendingPathComponent("application-activity.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [PowerSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([PowerSample].self, from: data)) ?? []
    }

    func save(_ samples: [PowerSample]) {
        write(Array(samples.filter { $0.capturedAt >= cutoff }.suffix(20_000)), to: fileURL)
    }

    func loadActivity() -> [AppActivityFrame] {
        guard let data = try? Data(contentsOf: activityURL), !data.isEmpty else { return [] }
        let frames: [AppActivityFrame]
        let firstByte = data.first { ![9, 10, 13, 32].contains($0) }
        if firstByte == 0x5B {
            frames = (try? decoder.decode([AppActivityFrame].self, from: data)) ?? []
        } else {
            frames = data.split(separator: 0x0A).compactMap {
                try? decoder.decode(AppActivityFrame.self, from: Data($0))
            }
        }
        let bounded = Array(frames.filter { $0.capturedAt >= cutoff }.suffix(30_000))
        if bounded.count != frames.count || firstByte == 0x5B {
            saveActivity(bounded)
        }
        return bounded
    }

    func appendActivity(_ frame: AppActivityFrame) {
        guard var data = try? encoder.encode(frame) else { return }
        data.append(0x0A)
        do {
            try FileManager.default.createDirectory(
                at: activityURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: activityURL.path) {
                try data.write(to: activityURL, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: activityURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            return
        }
    }

    func saveActivity(_ frames: [AppActivityFrame]) {
        let bounded = Array(frames.filter { $0.capturedAt >= cutoff }.suffix(30_000))
        var data = Data()
        for frame in bounded {
            guard let row = try? encoder.encode(frame) else { continue }
            data.append(row)
            data.append(0x0A)
        }
        do {
            try FileManager.default.createDirectory(
                at: activityURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: activityURL, options: .atomic)
        } catch {
            return
        }
    }

    private var cutoff: Date { Date().addingTimeInterval(-10 * 86_400) }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}
