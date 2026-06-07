import Foundation

// Manages auth state, the Discord Gateway WebSocket connection, and REST calls.
// v0.1 stub — wire in URLSessionWebSocketTask for the gateway and URLSession
// for REST once models are solid.
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

    // Token stored in UserDefaults for v0.1. Migrate to Keychain for production:
    // use Security framework SecItemAdd/SecItemCopyMatching with kSecClassGenericPassword.
    public var token: String {
        get { UserDefaults.standard.string(forKey: "rift.token") ?? "" }
        set { UserDefaults.standard.set(newValue.isEmpty ? nil : newValue, forKey: "rift.token") }
    }

    public var hasToken: Bool { !token.isEmpty }

    public func connect() async {
        guard hasToken else { return }
        state = .connecting

        // TODO: open wss://gateway.discord.gg/?v=10&encoding=json
        // TODO: handle Hello (op 10) → send Identify (op 2) with token
        // TODO: on READY event → set state = .connected(username:), populate guilds

        // Stub: surface an actionable error so the UI shows something useful
        try? await Task.sleep(nanoseconds: 600_000_000)
        state = .error("Gateway not implemented yet.")
    }

    public func disconnect() {
        // TODO: send Close frame on the WebSocket
        state = .disconnected
        guilds = []
    }
}
