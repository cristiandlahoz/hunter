import Darwin
import Foundation

actor ServerProbe {
    func scan() -> [DevServer]? {
        let sockets = CommandRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcnT"],
            timeout: 6
        )
        guard sockets.succeeded else { return nil }

        let processList = CommandRunner.run(
            "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,uid=,rss=,etime=,command="],
            timeout: 5
        )
        guard processList.succeeded else { return nil }
        let processes = Self.parseProcesses(processList.output)
        let currentUID = UInt32(getuid())
        let tunnels = Self.fetchTunnelsSynchronously()

        return Self.parseListeningSockets(sockets.output).compactMap { socket in
            guard let process = processes[socket.pid],
                  process.uid == currentUID,
                  Self.isLikelyDevelopmentServer(processName: socket.processName, command: process.command) else { return nil }
            let cwd = Self.currentDirectory(pid: socket.pid)
            guard cwd != "/" else { return nil }
            let project = Self.resolveProject(cwd: cwd, command: process.command)
            return DevServer(
                port: socket.port,
                pid: socket.pid,
                processName: socket.processName,
                command: process.command,
                workingDirectory: cwd,
                projectName: project.name,
                framework: project.framework,
                gitBranch: project.branch,
                memoryBytes: Self.processTreeMemory(rootPID: socket.pid, processes: processes),
                uptime: process.uptime,
                tunnel: tunnels.first { $0.localPort == socket.port }
            )
        }
        .filter { $0.processName != "Hunter" && $0.processName != "ngrok" }
        .sorted { lhs, rhs in
            if lhs.framework == "Vaadin" && rhs.framework != "Vaadin" { return true }
            if rhs.framework == "Vaadin" && lhs.framework != "Vaadin" { return false }
            return lhs.port < rhs.port
        }
    }

    nonisolated static func parseListeningSockets(_ text: String) -> [ListeningPort] {
        var pid: Int32?
        var command = ""
        var state = ""
        var name = ""
        var found: [String: ListeningPort] = [:]

        func flush() {
            guard state == "LISTEN", let pid, let port = port(from: name) else { return }
            found["\(pid):\(port)"] = ListeningPort(pid: pid, processName: command, port: port)
        }

        for rawLine in text.split(separator: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int32(value)
                state = ""
                name = ""
            case "c": command = value
            case "f":
                flush()
                state = ""
                name = ""
            case "n": name = value
            case "T" where value.hasPrefix("ST="): state = String(value.dropFirst(3))
            default: break
            }
        }
        flush()
        return found.values.sorted { $0.port < $1.port }
    }

    nonisolated static func port(from address: String) -> Int? {
        if let direct = Int(address) { return direct }
        guard let colon = address.lastIndex(of: ":") else { return nil }
        return Int(address[address.index(after: colon)...])
    }

    private nonisolated static func isLikelyDevelopmentServer(processName: String, command: String) -> Bool {
        let value = (processName + " " + command).lowercased()
        guard !value.contains(".app/contents/") else { return false }
        let markers = [
            "java", "node", "npm", "pnpm", "yarn", "bun", "deno",
            "python", "uvicorn", "gunicorn", "flask", "django",
            "ruby", "rails", "puma", "cargo", "target/debug", "go run",
            "php", "dotnet", "vite", "next dev", "webpack", "storybook"
        ]
        return markers.contains { value.contains($0) }
    }

    private struct ProcessDetails {
        let parentPID: Int32
        let uid: UInt32
        let memoryBytes: UInt64
        let uptime: TimeInterval?
        let command: String
    }

    private nonisolated static func parseProcesses(_ text: String) -> [Int32: ProcessDetails] {
        var result: [Int32: ProcessDetails] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 5, whereSeparator: { $0.isWhitespace })
            guard fields.count == 6,
                  let pid = Int32(fields[0]),
                  let parentPID = Int32(fields[1]),
                  let uid = UInt32(fields[2]),
                  let rss = UInt64(fields[3]) else { continue }
            result[pid] = ProcessDetails(
                parentPID: parentPID,
                uid: uid,
                memoryBytes: rss * 1_024,
                uptime: parseElapsed(String(fields[4])),
                command: String(fields[5])
            )
        }
        return result
    }

    private nonisolated static func processTreeMemory(rootPID: Int32, processes: [Int32: ProcessDetails]) -> UInt64 {
        var pending = [rootPID]
        var visited: Set<Int32> = []
        var total: UInt64 = 0
        while let pid = pending.popLast() {
            guard visited.insert(pid).inserted else { continue }
            total += processes[pid]?.memoryBytes ?? 0
            pending.append(contentsOf: processes.compactMap { childPID, details in
                details.parentPID == pid ? childPID : nil
            })
        }
        return total
    }

    private nonisolated static func parseElapsed(_ text: String) -> TimeInterval? {
        let dayParts = text.split(separator: "-", maxSplits: 1).map(String.init)
        let clock = (dayParts.count == 2 ? dayParts[1] : dayParts[0]).split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2 || clock.count == 3 else { return nil }
        let days = dayParts.count == 2 ? (Int(dayParts[0]) ?? 0) : 0
        let hours = clock.count == 3 ? clock[0] : 0
        let minutes = clock.count == 3 ? clock[1] : clock[0]
        let seconds = clock.last ?? 0
        return TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }

    private nonisolated static func currentDirectory(pid: Int32) -> String? {
        let result = CommandRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
            timeout: 3
        )
        return result.output.split(separator: "\n")
            .first { $0.hasPrefix("n/") }
            .map { String($0.dropFirst()) }
    }

    private nonisolated static func resolveProject(cwd: String?, command: String) -> (name: String, framework: String?, branch: String?) {
        guard let cwd else { return (URL(fileURLWithPath: command.split(separator: " ").first.map(String.init) ?? command).lastPathComponent, nil, nil) }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var directory = URL(fileURLWithPath: cwd)
        var root = directory
        var framework: String?

        while directory.path != "/" && directory.path != home {
            let path = directory.path
            let pom = path + "/pom.xml"
            let gradle = [path + "/build.gradle", path + "/build.gradle.kts"]
            let package = path + "/package.json"

            if fm.fileExists(atPath: pom) {
                root = directory
                let contents = (try? String(contentsOfFile: pom, encoding: .utf8))?.lowercased() ?? ""
                framework = contents.contains("vaadin") ? "Vaadin" : "Maven"
                break
            }
            if let buildFile = gradle.first(where: { fm.fileExists(atPath: $0) }) {
                root = directory
                let contents = (try? String(contentsOfFile: buildFile, encoding: .utf8))?.lowercased() ?? ""
                framework = contents.contains("vaadin") ? "Vaadin" : "Gradle"
                break
            }
            if fm.fileExists(atPath: package) {
                root = directory
                let contents = (try? String(contentsOfFile: package, encoding: .utf8))?.lowercased() ?? ""
                framework = javascriptFramework(contents)
                break
            }
            if fm.fileExists(atPath: path + "/pyproject.toml") { root = directory; framework = "Python"; break }
            if fm.fileExists(atPath: path + "/Cargo.toml") { root = directory; framework = "Rust"; break }
            if fm.fileExists(atPath: path + "/go.mod") { root = directory; framework = "Go"; break }
            directory.deleteLastPathComponent()
        }

        return (root.lastPathComponent.isEmpty ? URL(fileURLWithPath: cwd).lastPathComponent : root.lastPathComponent,
                framework,
                gitBranch(startingAt: root))
    }

    private nonisolated static func javascriptFramework(_ text: String) -> String {
        for (needle, label) in [("next", "Next.js"), ("vite", "Vite"), ("nuxt", "Nuxt"), ("svelte", "Svelte"), ("astro", "Astro"), ("express", "Express")] where text.contains("\"\(needle)") {
            return label
        }
        return "Node.js"
    }

    private nonisolated static func gitBranch(startingAt root: URL) -> String? {
        var directory = root
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        while directory.path != "/" && directory.path != home {
            let git = directory.appendingPathComponent(".git")
            var head = git.appendingPathComponent("HEAD")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue,
                   let pointer = try? String(contentsOf: git, encoding: .utf8),
                   pointer.hasPrefix("gitdir:") {
                    var path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.hasPrefix("/") { path = directory.appendingPathComponent(path).standardized.path }
                    head = URL(fileURLWithPath: path).appendingPathComponent("HEAD")
                }
                guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }
                let value = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.hasPrefix("ref: refs/heads/") ? String(value.dropFirst("ref: refs/heads/".count)) : String(value.prefix(7))
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private nonisolated static func fetchTunnelsSynchronously() -> [NgrokTunnel] {
        guard let url = URL(string: "http://127.0.0.1:4040/api/tunnels"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(NgrokResponse.self, from: data) else { return [] }
        return response.tunnels.compactMap { item in
            guard let publicURL = URL(string: item.publicURL), let port = port(from: item.config.addr) else { return nil }
            return NgrokTunnel(id: item.name, name: item.name, publicURL: publicURL, localPort: port)
        }
    }
}

private struct NgrokResponse: Decodable {
    let tunnels: [NgrokItem]
}

private struct NgrokItem: Decodable {
    let name: String
    let publicURL: String
    let config: NgrokConfig

    enum CodingKeys: String, CodingKey {
        case name, config
        case publicURL = "public_url"
    }
}

private struct NgrokConfig: Decodable {
    let addr: String
}
