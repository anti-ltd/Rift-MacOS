import SwiftUI

@MainActor
@Observable
public final class RiftModel {
    public var session = DiscordSession()
    public var selectedGuild: Guild?
    public var selectedChannel: Channel?

    public init() {}

    public func start() {
        if session.hasToken {
            Task { await session.connect() }
        }
    }
}
