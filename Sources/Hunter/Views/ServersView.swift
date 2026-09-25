import AppKit
import SwiftUI

struct ServersView: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(
                    title: "Local servers",
                    subtitle: "Listening development services and ngrok tunnels"
                ) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isRefreshing)
                }

                if let error = store.errorMessage {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                        Spacer()
                        if error.contains("authentication") {
                            Button("Open ngrok setup") { store.openNgrokSetup() }
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WattColors.critical)
                    .padding(12)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }

                if store.ngrokPath == nil || store.isInstallingNgrok || store.dependencyMessage != nil {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .foregroundStyle(WattColors.violet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.isInstallingNgrok ? "Installing ngrok…" : "ngrok dependency")
                                .font(.system(size: 12, weight: .semibold))
                            Text(store.dependencyMessage ?? "Install ngrok automatically to create public tunnels.")
                                .font(.system(size: 11))
                                .foregroundStyle(WattColors.secondary)
                        }
                        Spacer()
                        if store.isInstallingNgrok {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Install") { Task { await store.installNgrok() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                }

                Sheet {
                    VStack(spacing: 0) {
                        serverHeader
                        Divider().overlay(WattColors.rule)
                        if store.servers.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                                ServerRow(server: server, store: store)
                                    .background(index.isMultiple(of: 2) ? Color.white : WattColors.workspace.opacity(0.7))
                                if index < store.servers.count - 1 {
                                    Divider().overlay(WattColors.rule.opacity(0.75))
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text("Hunter reads local listening sockets with lsof. Tunnel traffic is handled by your installed ngrok agent; credentials stay in ngrok’s configuration.")
                }
                .font(.system(size: 11))
                .foregroundStyle(WattColors.secondary)
                .padding(.horizontal, 4)
            }
            .padding(22)
        }
        .background(WattColors.workspace)
        .onAppear { store.start() }
    }

    private var serverHeader: some View {
        HStack(spacing: 12) {
            Text("Project").frame(maxWidth: .infinity, alignment: .leading)
            Text("Port").frame(width: 56, alignment: .trailing)
            Text("Memory").frame(width: 72, alignment: .trailing)
            Text("Tunnel / actions").frame(width: 245, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(WattColors.secondary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color(red: 247/255, green: 249/255, blue: 251/255))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 25))
                .foregroundStyle(WattColors.violet)
            Text(store.isRefreshing ? "Scanning local ports…" : "No local servers found")
                .font(.system(size: 13, weight: .semibold))
            Text("Start a Vaadin or other development server and it will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(WattColors.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct ServerRow: View {
    let server: DevServer
    @ObservedObject var store: ServerStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    StatusDot(color: server.tunnel == nil ? WattColors.energy : WattColors.violet)
                    Text(server.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WattColors.ink)
                        .lineLimit(1)
                    if let framework = server.framework {
                        Text(framework)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(framework == "Vaadin" ? WattColors.violet : WattColors.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(framework == "Vaadin" ? WattColors.violetWash : WattColors.workspace, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(server.gitBranch ?? server.processName)
                    if let uptime = server.uptime { Text("· \(Formatters.duration(uptime))") }
                    if let directory = server.workingDirectory { Text("· \((directory as NSString).abbreviatingWithTildeInPath)") }
                }
                .font(.system(size: 10))
                .foregroundStyle(WattColors.secondary)
                .lineLimit(1)
                .help(server.command)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(server.port))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(WattColors.ink)
                .frame(width: 56, alignment: .trailing)

            Text(Formatters.memory(server.memoryBytes))
                .font(.system(size: 11, weight: server.memoryBytes >= store.memoryThresholdBytes ? .semibold : .regular))
                .foregroundStyle(server.memoryBytes >= store.memoryThresholdBytes ? WattColors.warning : WattColors.secondary)
                .tabularMeasurement()
                .frame(width: 72, alignment: .trailing)

            HStack(spacing: 7) {
                if store.busyPorts.contains(server.port) {
                    KillPulseIndicator()
                    Text("Stopping process…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WattColors.critical)
                } else {
                    if let tunnel = server.tunnel {
                        Button {
                            NSWorkspace.shared.open(tunnel.publicURL)
                        } label: {
                            Label("Open tunnel", systemImage: "arrow.up.right.square")
                        }
                        .help(tunnel.publicURL.absoluteString)

                        Button {
                            copy(tunnel.publicURL.absoluteString)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Copy public URL")

                        Button(role: .destructive) {
                            Task { await store.stopTunnel(tunnel) }
                        } label: {
                            Image(systemName: "link.badge.minus")
                        }
                        .help("Stop tunnel")
                    } else {
                        Button {
                            NSWorkspace.shared.open(server.localURL)
                        } label: {
                            Label("Open", systemImage: "safari")
                        }
                        Button {
                            Task { await store.startTunnel(for: server) }
                        } label: {
                            Label("ngrok", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        .help(store.ngrokPath == nil ? "Install ngrok to open a public tunnel" : "Open an ngrok tunnel")
                    }
                    Button(role: .destructive) {
                        Task { await store.stopServer(server) }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("Stop server process")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 245, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: store.busyPorts.contains(server.port))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
