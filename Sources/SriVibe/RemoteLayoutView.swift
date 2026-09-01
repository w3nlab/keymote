import SwiftUI
import SriVibeCore

enum RemoteLayoutRegistry {
    static let appleSiriRemoteA2854 = "apple-siri-remote-a2854"

    static func supports(_ layoutID: String?) -> Bool {
        layoutID == appleSiriRemoteA2854
    }
}

struct InteractiveRemoteLayout: View {
    @ObservedObject var model: AppModel
    let profile: AppProfile
    @Binding var selectedButton: RemoteButton

    private var language: AppLanguage { model.language }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            remote
                .frame(width: 300, height: 430)
            annotations
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    private var remote: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous).stroke(.secondary.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

            control(.up, icon: "chevron.up", x: 150, y: 78, size: 48)
            control(.left, icon: "chevron.left", x: 92, y: 132, size: 48)
            control(.center, icon: "circle.fill", x: 150, y: 132, size: 56)
            control(.right, icon: "chevron.right", x: 208, y: 132, size: 48)
            control(.down, icon: "chevron.down", x: 150, y: 186, size: 48)
            control(.back, icon: "chevron.left", x: 90, y: 255, size: 48)
            control(.tv, icon: "tv", x: 210, y: 255, size: 48)
            control(.playPause, icon: "playpause.fill", x: 150, y: 315, size: 60)
            control(.volumeUp, icon: "plus", x: 250, y: 345, size: 34)
            control(.volumeDown, icon: "minus", x: 250, y: 390, size: 34)
            control(.siri, icon: "waveform", x: 55, y: 365, size: 38)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Apple Siri Remote")
    }

    private var annotations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedButton.title(language)).font(.title3.weight(.semibold))
            MappingPickerRow(model: model, profile: profile, button: selectedButton)
            Divider().padding(.vertical, 2)
            Text(language == .chinese ? "按键图例" : "Button legend")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(RemoteButton.allCases, id: \.self) { button in
                        Button { selectedButton = button } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: button.icon).frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(button.title(language)).fontWeight(button == selectedButton ? .semibold : .regular)
                                    Text(summary(for: button)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(button == selectedButton ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func control(_ button: RemoteButton, icon: String, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        Button { selectedButton = button } label: {
            Image(systemName: icon)
                .font(.system(size: max(13, size * 0.32), weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(button == selectedButton ? .white : .primary)
                .background(button == selectedButton ? Color.accentColor : Color.primary.opacity(0.09), in: Circle())
                .overlay(Circle().stroke(.secondary.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .position(x: x, y: y)
        .accessibilityLabel(button.title(language))
        .help(summary(for: button))
    }

    private func summary(for button: RemoteButton) -> String {
        let tap = model.configuredAction(for: button, gesture: .tap, profile: profile)
        let hold = model.configuredAction(for: button, gesture: .hold, profile: profile)
        let tapLabel = actionTitle(tap)
        let holdLabel = actionTitle(hold)
        return language == .chinese ? "轻按：\(tapLabel) · 长按：\(holdLabel)" : "Tap: \(tapLabel) · Hold: \(holdLabel)"
    }

    private func actionTitle(_ action: RemoteAction) -> String {
        guard action == .launchSelectedApplication else { return action.title(language) }
        return language == .chinese ? "启动 \(model.tvApplicationName)" : "Launch \(model.tvApplicationName)"
    }
}

struct MappingPickerRow: View {
    @ObservedObject var model: AppModel
    let profile: AppProfile
    let button: RemoteButton

    var body: some View {
        HStack {
            picker(language == .chinese ? "轻按" : "Tap", .tap)
            picker(language == .chinese ? "长按" : "Hold", .hold)
        }
    }

    private var language: AppLanguage { model.language }

    private func picker(_ label: String, _ gesture: ButtonGesture) -> some View {
        Picker(label, selection: Binding(
            get: { model.configuredAction(for: button, gesture: gesture, profile: profile) },
            set: { model.setAction($0, for: button, gesture: gesture, profile: profile) }
        )) {
            ForEach(AppConfiguration.allowedActions(for: profile), id: \.self) { action in
                Text(action == .launchSelectedApplication ? (language == .chinese ? "启动 \(model.tvApplicationName)" : "Launch \(model.tvApplicationName)") : action.title(language)).tag(action)
            }
        }
    }
}

extension RemoteButton {
    var icon: String {
        switch self {
        case .up: "chevron.up"; case .down: "chevron.down"; case .left, .back: "chevron.left"; case .right: "chevron.right"
        case .center: "circle.fill"; case .tv: "tv"; case .playPause: "playpause.fill"; case .volumeUp: "plus"; case .volumeDown: "minus"; case .siri: "waveform"
        }
    }
}
