import Foundation

actor HistoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WattHound", isDirectory: true)
        fileURL = root.appendingPathComponent("power-samples.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [PowerSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([PowerSample].self, from: data)) ?? []
    }

    func save(_ samples: [PowerSample]) {
        let cutoff = Date().addingTimeInterval(-10 * 86_400)
        let bounded = Array(samples.filter { $0.capturedAt >= cutoff }.suffix(20_000))
        guard let data = try? encoder.encode(bounded) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
