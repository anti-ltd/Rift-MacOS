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

    static func sendMessage(channelID: String, content: String, token: String,
                            files: [(filename: String, data: Data, mimeType: String)] = []) async throws {
        let url = base.appendingPathComponent("channels/\(channelID)/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "Authorization")

        if files.isEmpty {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["content": content])
        } else {
            let boundary = "RiftBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = buildMultipart(boundary: boundary, content: content, files: files)
        }

        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw RiftError.httpError(code) }
    }

    private static func buildMultipart(boundary: String, content: String,
                                       files: [(filename: String, data: Data, mimeType: String)]) -> Data {
        var body = Data()
        func str(_ s: String) { body.append(Data(s.utf8)) }
        let nl = "\r\n"

        str("--\(boundary)\(nl)")
        str("Content-Disposition: form-data; name=\"payload_json\"\(nl)")
        str("Content-Type: application/json\(nl)\(nl)")
        if let json = try? JSONSerialization.data(withJSONObject: ["content": content]) { body.append(json) }
        str(nl)

        for (i, file) in files.enumerated() {
            str("--\(boundary)\(nl)")
            str("Content-Disposition: form-data; name=\"files[\(i)]\"; filename=\"\(file.filename)\"\(nl)")
            str("Content-Type: \(file.mimeType)\(nl)\(nl)")
            body.append(file.data)
            str(nl)
        }

        str("--\(boundary)--\(nl)")
        return body
    }

    // MARK: - Parser

    static func parseMessage(_ d: [String: Any]) -> Message? {
        guard let id = d["id"] as? String else { return nil }
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
        let attachments = parseAttachments(d["attachments"])
        let mentions = parseMentions(d["mentions"])
        let channelMentions = parseChannelMentions(d["mention_channels"])
        return Message(id: id, authorName: authorName, content: content,
                       authorID: authorID, authorAvatarURL: authorAvatarURL,
                       mentions: mentions, channelMentions: channelMentions,
                       attachments: attachments, timestamp: ts, isEdited: isEdited)
    }

    static func parseMentions(_ raw: Any?) -> [String: String] {
        guard let arr = raw as? [[String: Any]] else { return [:] }
        return Dictionary(uniqueKeysWithValues: arr.compactMap { u -> (String, String)? in
            guard let id = u["id"] as? String, let name = u["username"] as? String else { return nil }
            return (id, name)
        })
    }

    static func parseChannelMentions(_ raw: Any?) -> [String: String] {
        guard let arr = raw as? [[String: Any]] else { return [:] }
        return Dictionary(uniqueKeysWithValues: arr.compactMap { c -> (String, String)? in
            guard let id = c["id"] as? String, let name = c["name"] as? String else { return nil }
            return (id, name)
        })
    }

    static func parseAttachments(_ raw: Any?) -> [Attachment] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { a in
            guard let aid = a["id"] as? String, let url = a["url"] as? String else { return nil }
            return Attachment(
                id: aid, url: url,
                filename: a["filename"] as? String ?? "",
                contentType: a["content_type"] as? String,
                width: a["width"] as? Int,
                height: a["height"] as? Int
            )
        }
    }
}
