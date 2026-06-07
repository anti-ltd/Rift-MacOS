import Foundation

enum RiftError: Error, LocalizedError {
    case httpError(Int)
    var errorDescription: String? {
        if case .httpError(let code) = self { return "HTTP \(code)" }
        return nil
    }
}

enum DiscordREST {
    private static let base = URL(string: "https://discord.com/api/v10")!

    // MARK: - Messages

    static func fetchMessages(channelID: String, token: String, limit: Int = 50) async throws -> [Message] {
        var comps = URLComponents(
            url: base.appendingPathComponent("channels/\(channelID)/messages"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]

        var req = URLRequest(url: comps.url!)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw RiftError.httpError(code) }

        let raw = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        // Discord returns newest-first; reverse to chronological order
        return raw.compactMap(parseMessage).reversed()
    }

    static func sendMessage(channelID: String, content: String, token: String) async throws {
        let url = base.appendingPathComponent("channels/\(channelID)/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["content": content])

        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw RiftError.httpError(code) }
    }

    // MARK: - Parser

    static func parseMessage(_ d: [String: Any]) -> Message? {
        guard let id = d["id"] as? String else { return nil }
        let author = d["author"] as? [String: Any]
        let authorName = author?["username"] as? String ?? "Unknown"
        let content = d["content"] as? String ?? ""
        let isEdited: Bool
        if let et = d["edited_timestamp"] { isEdited = !(et is NSNull) } else { isEdited = false }
        let ts = (d["timestamp"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.now
        return Message(id: id, authorName: authorName, content: content, timestamp: ts, isEdited: isEdited)
    }
}
