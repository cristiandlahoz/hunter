import Foundation

struct DevServer: Identifiable, Sendable, Equatable {
    var id: String { "\(pid):\(port)" }
    let port: Int
    let pid: Int32
    let processName: String
    let command: String
    let workingDirectory: String?
    let projectName: String
    let framework: String?
    let gitBranch: String?
    let memoryBytes: UInt64
    let uptime: TimeInterval?
    var tunnel: NgrokTunnel?

    var localURL: URL { URL(string: "http://localhost:\(port)")! }
}

struct NgrokTunnel: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let publicURL: URL
    let localPort: Int
}

struct ListeningPort: Sendable, Equatable {
    let pid: Int32
    let processName: String
    let port: Int
}
