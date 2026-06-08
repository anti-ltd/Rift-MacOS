import Foundation

public enum GatewayEvent: Sendable {
    case ready(username: String, guilds: [Guild], dms: [Channel])
    case guildCreate(Guild)
    case messageCreate(channelID: String, message: Message)
    case error(String)
    case disconnected
}

// Manages the Discord Gateway WebSocket connection.
// Opcode flow: Hello (10) → Identify (2) → READY → heartbeat loop.
@MainActor
final class GatewayClient {
    private static let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json")!

    private var socket: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var lastSequence: Int?

    var onEvent: ((GatewayEvent) -> Void)?

    func connect(token: String) {
        socket = URLSession.shared.webSocketTask(with: Self.url)
        socket?.resume()
        Task { await receiveLoop(token: token) }
    }

    func disconnect() {
        heartbeatTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        lastSequence = nil
    }

    // MARK: - Receive loop

    private func receiveLoop(token: String) async {
        guard let socket else { return }
        do {
            while true {
                let msg = try await socket.receive()
                let data: Data
                switch msg {
                case .string(let s): data = Data(s.utf8)
                case .data(let d):   data = d
                @unknown default:    continue
                }
                handle(data: data, token: token)
            }
        } catch {
            onEvent?(.error(error.localizedDescription))
        }
    }

    private func handle(data: Data, token: String) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let op = json["op"] as? Int
        else { return }

        if let s = json["s"] as? Int { lastSequence = s }
        let t = json["t"] as? String
        let d = json["d"] as? [String: Any]

        switch op {
        case 10: // Hello — start heartbeat then identify
            let ms = d?["heartbeat_interval"] as? Double ?? 41_250
            startHeartbeat(interval: ms / 1000)
            Task { await sendIdentify(token: token) }
        case 11: // Heartbeat ACK
            break
        case 0:  // Dispatch
            handleDispatch(t: t, d: d)
        case 7:  // Reconnect
            onEvent?(.disconnected)
        case 9:  // Invalid Session
            onEvent?(.error("Invalid session — check your token."))
        default:
            break
        }
    }

    // MARK: - Dispatch

    private func handleDispatch(t: String?, d: [String: Any]?) {
        switch t {
        case "READY":
            let username = (d?["user"] as? [String: Any])?["username"] as? String ?? "Unknown"
            let rawGuilds = d?["guilds"] as? [[String: Any]] ?? []
            // private_channels: type 1 = DM, type 3 = group DM
            let rawDMs = d?["private_channels"] as? [[String: Any]] ?? []
            let dms = rawDMs.compactMap(parsePrivateChannel)
            onEvent?(.ready(username: username, guilds: rawGuilds.compactMap(parseGuild), dms: dms))
        case "GUILD_CREATE":
            if let d, let guild = parseGuild(d) { onEvent?(.guildCreate(guild)) }
        case "MESSAGE_CREATE":
            if let d, let channelID = d["channel_id"] as? String {
                onEvent?(.messageCreate(channelID: channelID, message: GatewayClient.parseMessage(d)))
            }
        default:
            break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(interval: TimeInterval) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { break }
                await self.send(["op": 1, "d": self.lastSequence as Any])
            }
        }
    }

    // MARK: - Identify

    private func sendIdentify(token: String) async {
        // capabilities: 0 → Discord sends full GUILD_CREATE events instead of
        // lazy-load stubs that require op 14 subscriptions to hydrate.
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "capabilities": 0,
                "properties": [
                    "os": "Mac OS X",
                    "browser": "Discord Client",
                    "device": ""
                ] as [String: Any]
            ] as [String: Any]
        ]
        await send(payload)
    }

    // MARK: - Send

    private func send(_ json: [String: Any]) async {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: json),
              let str = String(data: data, encoding: .utf8) else { return }
        try? await socket.send(.string(str))
    }

    // MARK: - Parsers

    private func parseGuild(_ d: [String: Any]) -> Guild? {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        let icon = d["icon"] as? String
        let iconURL = icon.map { "https://cdn.discordapp.com/icons/\(id)/\($0).png?size=64" }
        let rawChannels = d["channels"] as? [[String: Any]] ?? []
        // Active threads are in a separate top-level key in GUILD_CREATE
        let rawThreads = d["threads"] as? [[String: Any]] ?? []
        let channels = (rawChannels + rawThreads).compactMap(parseChannel)
        return Guild(id: id, name: name, iconURL: iconURL, channels: channels)
    }

    private func parsePrivateChannel(_ d: [String: Any]) -> Channel? {
        guard let id = d["id"] as? String, let typeInt = d["type"] as? Int else { return nil }
        let name: String
        switch typeInt {
        case 1: // DM — use the other recipient's username
            let recipients = d["recipients"] as? [[String: Any]] ?? []
            name = recipients.first?["username"] as? String ?? "Unknown"
        case 3: // Group DM — prefer explicit name, fall back to recipient list
            if let n = d["name"] as? String, !n.isEmpty {
                name = n
            } else {
                let recipients = d["recipients"] as? [[String: Any]] ?? []
                name = recipients.compactMap { $0["username"] as? String }.joined(separator: ", ")
            }
        default: return nil
        }
        return Channel(id: id, name: name, kind: .text, position: 0)
    }

    private func parseChannel(_ d: [String: Any]) -> Channel? {
        guard
            let id = d["id"] as? String,
            let typeInt = d["type"] as? Int,
            let name = d["name"] as? String, !name.isEmpty
        else { return nil }
        let kind: Channel.Kind
        switch typeInt {
        case 0:  kind = .text
        case 2:  kind = .voice
        case 4:  kind = .category
        case 5:  kind = .announcement
        case 10: kind = .publicThread
        case 11: kind = .privateThread
        case 12: kind = .announcementThread
        case 13: kind = .stage
        case 15: kind = .forum
        default: return nil
        }
        let position = d["position"] as? Int ?? 0
        let parentID = d["parent_id"] as? String
        return Channel(id: id, name: name, kind: kind, position: position, parentID: parentID)
    }

    private static func parseMessage(_ d: [String: Any]) -> Message {
        let id = d["id"] as? String ?? UUID().uuidString
        let author = d["author"] as? [String: Any]
        let authorName = author?["username"] as? String ?? "Unknown"
        let authorID = author?["id"] as? String
        let authorAvatarURL: String? = {
            guard let uid = authorID, let hash = author?["avatar"] as? String else { return nil }
            return "https://cdn.discordapp.com/avatars/\(uid)/\(hash).png?size=64"
        }()
        let content = d["content"] as? String ?? ""
        let isEdited: Bool
        if let et = d["edited_timestamp"] { isEdited = !(et is NSNull) } else { isEdited = false }
        let ts = (d["timestamp"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.now
        let attachments = DiscordREST.parseAttachments(d["attachments"])
        let mentions = DiscordREST.parseMentions(d["mentions"])
        let channelMentions = DiscordREST.parseChannelMentions(d["mention_channels"])
        let reactions = DiscordREST.parseReactions(d["reactions"])
        return Message(id: id, authorName: authorName, content: content,
                       authorID: authorID, authorAvatarURL: authorAvatarURL,
                       mentions: mentions, channelMentions: channelMentions,
                       attachments: attachments, reactions: reactions,
                       timestamp: ts, isEdited: isEdited)
    }
}
