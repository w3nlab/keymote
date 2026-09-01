import Foundation

public final class ConfigurationStore {
    private let defaults: UserDefaults
    private let key = "Keymote.configuration.v1"
    private let legacyKey = "SriVibe.configuration.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> AppConfiguration {
        guard let data = defaults.data(forKey: key) ?? defaults.data(forKey: legacyKey),
              let value = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration()
        }
        var configuration = value
        for profile in [AppProfile.otty, .chrome, .edge] {
            if configuration.mappings[profile] == nil, let defaults = AppConfiguration.defaultMappings[profile] {
                configuration.mappings[profile] = defaults
            }
        }
        configuration = configuration.normalized()
        for profile in AppProfile.allCases where profile != .default {
            guard var mapping = configuration.mappings[profile] else { continue }
            mapping.set(.useDefault, for: .tv, gesture: .tap)
            mapping.set(.useDefault, for: .tv, gesture: .hold)
            configuration.mappings[profile] = mapping
        }
        for profile in AppProfile.allCases where profile != .default && profile != .chrome && profile != .edge {
            guard var mapping = configuration.mappings[profile] else { continue }
            mapping.set(.none, for: .playPause, gesture: .tap)
            mapping.set(.none, for: .playPause, gesture: .hold)
            configuration.mappings[profile] = mapping
        }
        for profile in AppProfile.allCases {
            guard var mapping = configuration.mappings[profile], let defaults = AppConfiguration.defaultMappings[profile] else { continue }
            if !profile.supportsTabs {
                mapping.bindings.removeAll { binding in
                    (binding.button == .volumeUp || binding.button == .volumeDown) &&
                    (binding.action == .adjustVolumeUp || binding.action == .adjustVolumeDown)
                }
            }
            for button in [RemoteButton.volumeUp, .volumeDown, .mute] where !mapping.bindings.contains(where: { $0.button == button }) {
                for gesture in ButtonGesture.allCases {
                    let action = defaults.action(for: button, gesture: gesture)
                    if action != .none { mapping.set(action, for: button, gesture: gesture) }
                }
            }
            configuration.mappings[profile] = mapping
        }
        // Add the Back long-press default for configurations created before the
        // quit-current-application action existed, without replacing a choice
        // the user has already made for that gesture.
        for profile in AppProfile.allCases {
            guard var mapping = configuration.mappings[profile],
                  !mapping.bindings.contains(where: { $0.button == .back && $0.gesture == .hold })
            else { continue }
            mapping.set(.quitApplication, for: .back, gesture: .hold)
            configuration.mappings[profile] = mapping
        }
        // Existing configurations predate the TV-hold binding. Add the new
        // default only when the user has not assigned that gesture themselves.
        for profile in AppProfile.allCases {
            guard var mapping = configuration.mappings[profile],
                  !mapping.bindings.contains(where: { $0.button == .tv && $0.gesture == .hold })
            else { continue }
            mapping.set(.switchApplication, for: .tv, gesture: .hold)
            configuration.mappings[profile] = mapping
        }
        return configuration
    }

    public func save(_ configuration: AppConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}
