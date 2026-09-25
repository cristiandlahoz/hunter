import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination
    @ObservedObject var store: EnergyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Hunter")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 58)

            VStack(spacing: 4) {
                ForEach(SidebarDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: destination.symbol)
                                .frame(width: 18)
                            Text(destination.rawValue)
                                .fontWeight(selection == destination ? .semibold : .regular)
                            Spacer()
                        }
                        .foregroundStyle(selection == destination ? Color.white : WattColors.sidebarText)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(
                            selection == destination ? WattColors.sidebarHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(destination.shortcut), modifiers: .command)
                    .accessibilityLabel(destination.rawValue)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    StatusDot(color: store.snapshot.isOnAC ? WattColors.violet : WattColors.energy)
                    Text(store.snapshot.isOnAC ? "Power adapter" : "On battery")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("\(store.snapshot.percentage)% · \(Formatters.time(store.snapshot.timeRemainingMinutes)) remaining")
                    .font(.system(size: 12))
                    .foregroundStyle(WattColors.sidebarMuted)
                    .tabularMeasurement()
            }
            .foregroundStyle(WattColors.sidebarText)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.12)) }
        }
        .frame(width: 224)
        .background(WattColors.sidebar)
    }
}
