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
        GeometryReader { proxy in
            let remoteWidth = min(max(210, proxy.size.width * 0.30), 320)
            let scale = remoteWidth / 210
            let remoteHeight = 520 * scale
            HStack(alignment: .top, spacing: max(24, proxy.size.width * 0.035)) {
                remote
                    .frame(width: 210, height: 520)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: remoteWidth, height: remoteHeight, alignment: .topLeading)
                annotations
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(420, min(560, remoteHeight - 24)))
            }
            .padding(32)
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(minHeight: 620)
    }

    private var remote: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                .frame(width: 132, height: 500)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.secondary.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

            Circle().fill(Color.primary.opacity(0.08)).frame(width: 106, height: 106).position(x: 105, y: 88)
            control(.up, icon: "chevron.up", x: 105, y: 45, size: 37)
            control(.left, icon: "chevron.left", x: 62, y: 88, size: 37)
            control(.center, icon: "circle.fill", x: 105, y: 88, size: 46)
            control(.right, icon: "chevron.right", x: 148, y: 88, size: 37)
            control(.down, icon: "chevron.down", x: 105, y: 131, size: 37)
            control(.back, icon: "chevron.left", x: 72, y: 180, size: 43)
            control(.tv, icon: "tv", x: 138, y: 180, size: 43)
            // Lower controls form two inset vertical columns: media on the left
            // and volume on the right, with clear margins from the body edge.
            control(.playPause, icon: "playpause.fill", x: 72, y: 244, size: 38)
            control(.mute, icon: "speaker.slash.fill", x: 72, y: 293, size: 38)
            control(.volumeUp, icon: "plus", x: 138, y: 244, size: 34)
            control(.volumeDown, icon: "minus", x: 138, y: 293, size: 34)
            // Siri is a dedicated side button on the right edge of Apple's USB-C Siri Remote.
            control(.siri, icon: "waveform", x: 190, y: 205, size: 34)
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
            ScrollViewReader { proxy in
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .id(button)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: selectedButton) { _, button in
                    withAnimation { proxy.scrollTo(button, anchor: .center) }
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
        let doubleTap = model.configuredAction(for: button, gesture: .doubleTap, profile: profile)
        let hold = model.configuredAction(for: button, gesture: .hold, profile: profile)
        let tapLabel = actionTitle(tap)
        let doubleTapLabel = actionTitle(doubleTap)
        let holdLabel = actionTitle(hold)
        return language == .chinese ? "轻按：\(tapLabel) · 双击：\(doubleTapLabel) · 长按：\(holdLabel)" : "Tap: \(tapLabel) · Double tap: \(doubleTapLabel) · Hold: \(holdLabel)"
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
            picker(language == .chinese ? "双击" : "Double tap", .doubleTap)
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
        case .center: "circle.fill"; case .tv: "tv"; case .playPause: "playpause.fill"; case .mute: "speaker.slash.fill"; case .volumeUp: "plus"; case .volumeDown: "minus"; case .siri: "waveform"
        }
    }
}
