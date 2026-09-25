import AppKit
import SwiftUI

struct ApplicationLedger: View {
    let applications: [AppImpact]
    var limit: Int? = nil

    private var displayed: [AppImpact] {
        limit.map { Array(applications.prefix($0)) } ?? applications
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Application")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU")
                    .frame(width: 80, alignment: .trailing)
                Text("Memory")
                    .frame(width: 92, alignment: .trailing)
                Text("Impact")
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WattColors.secondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Color(red: 247/255, green: 249/255, blue: 251/255))

            Divider().overlay(WattColors.rule)

            if displayed.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 24))
                        .foregroundStyle(WattColors.violet)
                    Text("Collecting application activity")
                        .font(.system(size: 13, weight: .medium))
                    Text("The first ranking appears after a monitoring sample.")
                        .font(.system(size: 11))
                        .foregroundStyle(WattColors.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, app in
                    HStack(spacing: 10) {
                        AppIcon(path: app.executablePath)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WattColors.ink)
                                .lineLimit(1)
                            if app.processCount > 1 {
                                Text("\(app.processCount) processes")
                                    .font(.system(size: 10))
                                    .foregroundStyle(WattColors.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.1f%%", app.cpuPercentage))
                            .frame(width: 80, alignment: .trailing)
                        Text(Formatters.memory(app.memoryBytes))
                            .frame(width: 92, alignment: .trailing)
                        ImpactBar(value: app.relativeImpact, maximum: applications.first?.relativeImpact ?? 1)
                            .frame(width: 120)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(WattColors.secondary)
                    .tabularMeasurement()
                    .padding(.horizontal, 16)
                    .frame(height: 43)
                    .background(index.isMultiple(of: 2) ? Color.white : WattColors.workspace.opacity(0.34))
                    .overlay(alignment: .bottom) { Divider().overlay(WattColors.rule.opacity(0.7)) }
                }
            }
        }
    }
}

private struct ImpactBar: View {
    let value: Double
    let maximum: Double

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WattColors.rule)
                    Capsule()
                        .fill(value > maximum * 0.7 ? WattColors.warning : WattColors.violet)
                        .frame(width: max(3, proxy.size.width * min(1, value / max(maximum, 0.1))))
                }
            }
            .frame(height: 5)
            Text(String(format: "%.1f", value))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Relative impact \(String(format: "%.1f", value))")
    }
}

struct AppIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        guard !path.isEmpty else { return NSWorkspace.shared.icon(for: .application) }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
