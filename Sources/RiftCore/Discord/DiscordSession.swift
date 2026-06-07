import Foundation

@MainActor
@Observable
public final class DiscordSession {

    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(username: String)
        case error(String)

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    public var state: State = .disconnected
    public var guilds: [Guild] = []
    public var directMessages: [Channel] = []
    // Live messages per channel, appended on MESSAGE_CREATE gateway events
    public var liveMessages: [String: [Message]] = [:]

    private var gateway: GatewayClient?

    // Token stored in UserDefaults for v0.1. Migrate to Keychain for production.
    public var token: String {
        get { UserDefaults.standard.string(forKey: "rift.token") ?? "" }
        set { UserDefaults.standard.set(newValue.isEmpty ? nil : newValue, forKey: "rift.token") }
    }

    public var hasToken: Bool { !token.isEmpty }

    public func connect() {
        guard hasToken else { return }
        gateway?.disconnect()
        state = .connecting
        guilds = []
        directMessages = []
        liveMessages = [:]

        let client = GatewayClient()
        client.onEvent = { [weak self] event in self?.handle(event) }
        gateway = client
        client.connect(token: token)
    }

    public func disconnect() {
        gateway?.disconnect()
        gateway = nil
        state = .disconnected
        guilds = []
        directMessages = []
        liveMessages = [:]
    }

    private func handle(_ event: GatewayEvent) {
        switch event {
        case .ready(let username, let initial, let dms):
            state = .connected(username: username)
            guilds = initial.sorted { $0.name < $1.name }
            directMessages = dms.sorted { $0.name < $1.name }
        case .guildCreate(let guild):
            if !guilds.contains(where: { $0.id == guild.id }) {
                guilds.append(guild)
                guilds.sort { $0.name < $1.name }
            }
        case .messageCreate(let channelID, let message):
            liveMessages[channelID, default: []].append(message)
        case .error(let msg):
            state = .error(msg)
        case .disconnected:
            state = .disconnected
        }
    }
}
