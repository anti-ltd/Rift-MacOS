import SwiftUI

@MainActor
@Observable
public final class RiftModel {
    public var session = DiscordSession()
    public var selectedGuild: Guild?
    public var selectedChannel: Channel? {
        didSet {
            session.selectedChannelID = selectedChannel?.id
            if let id = selectedChannel?.id { session.clearUnread(channelID: id) }
        }
    }

    public init() {}

    public func start() {
        if session.hasToken { session.connect() }
    }
}
