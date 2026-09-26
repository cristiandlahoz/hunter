import XCTest
@testable import Hunter

final class ServerProbeTests: XCTestCase {
    func testParsesListeningSocketsAndDeduplicatesIPv4AndIPv6() {
        let text = """
        p4002
        cjava
        f8
        n127.0.0.1:8080
        TST=LISTEN
        f9
        n[::1]:8080
        TST=LISTEN
        p5000
        cnode
        f10
        n*:3000
        TST=LISTEN
        """

        let sockets = ServerProbe.parseListeningSockets(text)

        XCTAssertEqual(sockets, [
            ListeningPort(pid: 5000, processName: "node", port: 3000),
            ListeningPort(pid: 4002, processName: "java", port: 8080)
        ])
    }

    func testParsesPortFromIPv4IPv6AndNgrokAddresses() {
        XCTAssertEqual(ServerProbe.port(from: "127.0.0.1:8080"), 8080)
        XCTAssertEqual(ServerProbe.port(from: "[::1]:8081"), 8081)
        XCTAssertEqual(ServerProbe.port(from: "http://localhost:8082"), 8082)
        XCTAssertEqual(ServerProbe.port(from: "8083"), 8083)
        XCTAssertNil(ServerProbe.port(from: "localhost"))
    }

    func testExcludesBrowserAgentAndDebuggerButKeepsVaadinHTTPListener() {
        let java = "/bin/java -Xrunjdwp:transport=dt_socket,server=y,address=5630 -cp target/classes com.example.Application"
        XCTAssertFalse(ServerProbe.isLikelyDevelopmentServer(processName: "java", command: java, port: 5630))
        XCTAssertTrue(ServerProbe.isLikelyDevelopmentServer(processName: "java", command: java, port: 8444))
        XCTAssertFalse(ServerProbe.isLikelyDevelopmentServer(
            processName: "agent-bro",
            command: "/opt/homebrew/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64",
            port: 61285
        ))
    }
}
