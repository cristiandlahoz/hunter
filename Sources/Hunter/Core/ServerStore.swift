import AppKit
import Darwin
import Foundation

@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [DevServer] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyPorts: Set<Int> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isInstallingNgrok = false
    @Published private(set) var dependencyMessage: String?

    private let probe = ServerProbe()
    private let notificationService = NotificationService()
    private var refreshTimer: Timer?
    private var ngrokProcesses: [Int: Process] = [:]

    var ngrokPath: String? {
        [
            Self.managedNgrokURL.path,
            "/opt/homebrew/bin/ngrok",
            "/usr/local/bin/ngrok",
            "/usr/bin/ngrok"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static var managedNgrokURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hunter/bin/ngrok")
    }

    var memoryThresholdBytes: UInt64 {
        let gigabytes = max(0.25, UserDefaults.standard.double(forKey: "serverMemoryThresholdGB"))
        return UInt64(gigabytes * 1_073_741_824)
    }

    func start() {
        guard refreshTimer == nil else { return }
        Task {
            if UserDefaults.standard.bool(forKey: "serverMemoryAlertsEnabled") {
                _ = await notificationService.requestAuthorization()
            }
            await refresh()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        guard let scannedServers = await probe.scan() else {
            errorMessage = "Hunter couldn’t scan listening ports. Existing server data was kept; try refreshing."
            isRefreshing = false
            return
        }
        servers = scannedServers
        isRefreshing = false
        if errorMessage?.contains("scan listening ports") == true { errorMessage = nil }
        await notificationService.evaluateServerMemory(
            servers: scannedServers,
            thresholdBytes: memoryThresholdBytes,
            enabled: UserDefaults.standard.bool(forKey: "serverMemoryAlertsEnabled")
        )
    }

    func startTunnel(for server: DevServer) async {
        guard server.tunnel == nil, !busyPorts.contains(server.port) else { return }
        busyPorts.insert(server.port)
        errorMessage = nil
        defer { busyPorts.remove(server.port) }

        if await createTunnelThroughAgent(port: server.port) {
            try? await Task.sleep(for: .milliseconds(500))
            await refresh()
            return
        }

        guard await ensureNgrokAvailable(), let ngrokPath else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ngrokPath)
        process.arguments = ["http", String(server.port), "--log", "stdout", "--log-format", "json"]
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            ngrokProcesses[server.port] = process
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(1))
                await refresh()
                if servers.contains(where: { $0.port == server.port && $0.tunnel != nil }) { return }
                if !process.isRunning { break }
            }
            ngrokProcesses.removeValue(forKey: server.port)
            if !process.isRunning {
                let details = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                errorMessage = details?.isEmpty == false ? "ngrok couldn’t start: \(details!)" : "ngrok couldn’t start."
            } else {
                process.terminate()
                errorMessage = "ngrok needs authentication. Open ngrok setup, add your authtoken, then try again."
            }
        } catch {
            errorMessage = "Couldn’t start ngrok: \(error.localizedDescription)"
        }
    }

    func installNgrok() async {
        guard !isInstallingNgrok, ngrokPath == nil else { return }
        isInstallingNgrok = true
        dependencyMessage = "Installing ngrok…"
        defer { isInstallingNgrok = false }

        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            var result = await Task.detached { CommandRunner.run(brew, arguments: ["install", "ngrok"], timeout: 180) }.value
            if !result.succeeded {
                result = await Task.detached { CommandRunner.run(brew, arguments: ["install", "ngrok/ngrok/ngrok"], timeout: 180) }.value
            }
            if result.succeeded, ngrokPath != nil {
                dependencyMessage = nil
                errorMessage = nil
                return
            }
        }

        dependencyMessage = "Downloading ngrok to Hunter’s Application Support folder…"
        do {
            try await installManagedNgrok()
            dependencyMessage = nil
            errorMessage = nil
        } catch {
            dependencyMessage = "Hunter couldn’t install ngrok automatically: \(error.localizedDescription)"
        }
    }

    func openNgrokSetup() {
        if let url = URL(string: "https://dashboard.ngrok.com/get-started/your-authtoken") {
            NSWorkspace.shared.open(url)
        }
    }

    func stopServer(_ server: DevServer) async {
        guard !busyPorts.contains(server.port) else { return }
        busyPorts.insert(server.port)
        errorMessage = nil
        defer { busyPorts.remove(server.port) }

        if let tunnel = server.tunnel {
            await deleteTunnel(tunnel)
            if let process = ngrokProcesses.removeValue(forKey: tunnel.localPort), process.isRunning {
                process.terminate()
            }
        }

        guard Darwin.kill(server.pid, SIGTERM) == 0 else {
            errorMessage = "Couldn’t stop \(server.projectName). The process may have already exited."
            await refresh()
            return
        }
        try? await Task.sleep(for: .seconds(2))
        if Darwin.kill(server.pid, 0) == 0 { Darwin.kill(server.pid, SIGKILL) }
        await refresh()
    }

    func stopTunnel(_ tunnel: NgrokTunnel) async {
        busyPorts.insert(tunnel.localPort)
        errorMessage = nil
        defer { busyPorts.remove(tunnel.localPort) }

        await deleteTunnel(tunnel)
        if let process = ngrokProcesses.removeValue(forKey: tunnel.localPort), process.isRunning {
            process.terminate()
        }
        try? await Task.sleep(for: .milliseconds(500))
        await refresh()
    }

    private func installManagedNgrok() async throws {
        #if arch(arm64)
        let download = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip"
        #else
        let download = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip"
        #endif
        guard let url = URL(string: download) else { throw URLError(.badURL) }
        let (archiveURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let extractionURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hunter-ngrok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionURL) }
        let result = await Task.detached {
            CommandRunner.run("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionURL.path], timeout: 30)
        }.value
        guard result.succeeded else {
            throw NSError(domain: "Hunter.NgrokInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: result.error])
        }

        let extractedBinary = extractionURL.appendingPathComponent("ngrok")
        let destination = Self.managedNgrokURL
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: extractedBinary, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private func ensureNgrokAvailable() async -> Bool {
        if ngrokPath != nil { return true }
        await installNgrok()
        guard ngrokPath != nil else {
            errorMessage = dependencyMessage ?? "ngrok is unavailable."
            return false
        }
        return true
    }

    private func deleteTunnel(_ tunnel: NgrokTunnel) async {
        var components = URLComponents(string: "http://127.0.0.1:4040/api/tunnels/")!
        components.path += tunnel.name
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }

    private func createTunnelThroughAgent(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:4040/api/tunnels") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": "hunter-\(port)",
            "addr": String(port),
            "proto": "http"
        ])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
