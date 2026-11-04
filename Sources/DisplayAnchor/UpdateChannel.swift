import Foundation

enum UpdateChannel: String, CaseIterable {
    case stable
    case releaseCandidate

    var allowedChannels: Set<String> {
        switch self {
        case .stable: []
        case .releaseCandidate: ["rc"]
        }
    }

    func allows(_ channel: String?) -> Bool {
        guard let channel, !channel.isEmpty else { return true }
        return allowedChannels.contains(channel)
    }
}
