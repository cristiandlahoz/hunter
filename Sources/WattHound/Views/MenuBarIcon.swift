import AppKit
import SwiftUI

enum MenuBarIcon {
    static let trackingHound: NSImage = loadSVG(named: "BloodhoundFrame1")

    private static func loadSVG(named name: String) -> NSImage {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "Resources"
        ), let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "WattHound")!
        }

        // The SVG carries its own violet color so the hound remains a branded,
        // full-color status item instead of being flattened into a template.
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = false
        image.accessibilityDescription = "WattHound bloodhound"
        return image
    }
}

struct AnimatedMenuBarHound: View {
    @State private var isSniffing = false

    var body: some View {
        Image(nsImage: MenuBarIcon.trackingHound)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(isSniffing ? -1.2 : 1.2), anchor: .bottomTrailing)
            .offset(y: isSniffing ? 0.6 : -0.4)
            .animation(
                .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                value: isSniffing
            )
            .onAppear { isSniffing = true }
            .accessibilityHidden(true)
    }
}
