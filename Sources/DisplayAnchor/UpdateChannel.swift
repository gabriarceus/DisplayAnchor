import Foundation

/// Update channel selected in settings.
enum UpdateChannel: String, CaseIterable {
    case stable
    case releaseCandidate

    /// Sparkle channel names offered in addition to the default (stable) channel.
    var allowedChannels: Set<String> {
        switch self {
        case .stable: []
        case .releaseCandidate: ["rc"]
        }
    }

    /// Whether an item on `channel` may be offered; nil or empty means the default channel.
    func allows(_ channel: String?) -> Bool {
        guard let channel, !channel.isEmpty else { return true }
        return allowedChannels.contains(channel)
    }
}
