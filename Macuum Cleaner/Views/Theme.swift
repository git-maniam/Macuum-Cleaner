import SwiftUI
import MacuumCore

extension JunkCategory {
    var symbol: String {
        switch self {
        case .systemCaches: "gearshape.2.fill"
        case .appCaches: "square.stack.3d.up.fill"
        case .logs: "doc.text.fill"
        case .tempFiles: "clock.arrow.circlepath"
        case .trash: "trash.fill"
        case .browserData: "globe"
        case .appRemnants: "app.dashed"
        case .developerJunk: "hammer.fill"
        case .iOSBackups: "iphone"
        case .languageFiles: "character.bubble.fill"
        case .brokenPrefs: "slider.horizontal.3"
        case .downloadJunk: "arrow.down.circle.fill"
        case .duplicates: "doc.on.doc.fill"
        case .dsStore: "folder.fill"
        case .fontCaches: "textformat"
        case .quickLookCaches: "eye.fill"
        case .mailJunk: "envelope.fill"
        case .packageManagers: "shippingbox.fill"
        case .notificationHistory: "bell.fill"
        case .spotlightExternal: "externaldrive.fill"
        case .iCloudConflicts: "icloud.fill"
        case .screenshots: "camera.viewfinder"
        case .vmDockerLeftovers: "server.rack"
        case .timeMachineSnapshots: "clock.arrow.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .systemCaches, .appCaches, .mailJunk: .blue
        case .logs, .spotlightExternal: .gray
        case .tempFiles, .duplicates: .orange
        case .trash, .notificationHistory: .red
        case .browserData: .teal
        case .appRemnants, .vmDockerLeftovers: .purple
        case .developerJunk, .fontCaches: .indigo
        case .iOSBackups, .timeMachineSnapshots: .green
        case .languageFiles, .screenshots: .pink
        case .brokenPrefs: .mint
        case .downloadJunk, .iCloudConflicts: .cyan
        case .dsStore, .packageManagers: .brown
        case .quickLookCaches: .yellow
        }
    }
}

/// Rounded colored tile with a white SF Symbol, in the style of Settings/App Store lists.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Large pill button used for the primary actions (Scan Now, Clean Selected, Uninstall).
struct PrimaryActionStyle: ButtonStyle {
    var tint: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.9), tint], startPoint: .top, endPoint: .bottom))
                    .shadow(color: tint.opacity(isEnabled ? 0.35 : 0), radius: 8, y: 3)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryActionStyle {
    static func primaryAction(_ tint: Color = .accentColor) -> PrimaryActionStyle { PrimaryActionStyle(tint: tint) }
}
