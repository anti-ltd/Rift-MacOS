import Foundation

public struct Guild: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var iconURL: String?
    public var channels: [Channel]

    public init(id: String, name: String, iconURL: String? = nil, channels: [Channel] = []) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.channels = channels
    }

    public var initial: String { String(name.prefix(1)).uppercased() }
}

public struct Channel: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case text, voice, announcement, forum, stage, category
        case publicThread, privateThread, announcementThread

        public var symbol: String {
            switch self {
            case .text:               return "number"
            case .voice:              return "speaker.wave.2"
            case .announcement:       return "megaphone"
            case .forum:              return "list.bullet.rectangle"
            case .stage:              return "person.wave.2"
            case .category:           return "folder"
            case .publicThread:       return "text.bubble"
            case .privateThread:      return "lock"
            case .announcementThread: return "text.bubble"
            }
        }
    }

    public let id: String
    public var name: String
    public var kind: Kind
    public var position: Int
    public var unreadCount: Int
    public var parentID: String?

    public var isCategory: Bool { kind == .category }
    public var isThread: Bool {
        kind == .publicThread || kind == .privateThread || kind == .announcementThread
    }

    public init(id: String, name: String, kind: Kind = .text, position: Int = 0,
                unreadCount: Int = 0, parentID: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.position = position
        self.unreadCount = unreadCount
        self.parentID = parentID
    }
}

public struct Reaction: Identifiable, Hashable, Sendable {
    public let emojiName: String   // unicode char OR custom name
    public let emojiID: String?    // nil for standard unicode emoji
    public var count: Int
    public var me: Bool            // current user has reacted

    public init(emojiName: String, emojiID: String? = nil, count: Int = 0, me: Bool = false) {
        self.emojiName = emojiName
        self.emojiID = emojiID
        self.count = count
        self.me = me
    }

    /// Identifiable key
    public var id: String { emojiID.map { "\(emojiName):\($0)" } ?? emojiName }

    /// What to show in the UI (unicode char, or :name: for custom)
    public var display: String { emojiID == nil ? emojiName : ":\(emojiName):" }

    /// URL path segment for the Discord REST API
    public var apiParam: String { emojiID.map { "\(emojiName):\($0)" } ?? emojiName }
}

public struct Attachment: Identifiable, Sendable {
    public let id: String
    public let url: String
    public let filename: String
    public let contentType: String?
    public let width: Int?
    public let height: Int?

    public init(id: String, url: String, filename: String,
                contentType: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.url = url
        self.filename = filename
        self.contentType = contentType
        self.width = width
        self.height = height
    }

    public var isImage: Bool {
        if let ct = contentType { return ct.hasPrefix("image/") }
        return ["png", "jpg", "jpeg", "gif", "webp"].contains(fileExtension)
    }

    public var isVideo: Bool {
        if let ct = contentType { return ct.hasPrefix("video/") }
        return ["mp4", "mov", "webm"].contains(fileExtension)
    }

    public var isAnimated: Bool {
        contentType == "image/gif" || fileExtension == "gif"
    }

    private var fileExtension: String {
        String(url.split(separator: "?").first ?? "")
            .split(separator: "/").last
            .map(String.init)?
            .split(separator: ".")
            .last
            .map { String($0).lowercased() } ?? ""
    }
}

public struct Message: Identifiable, Sendable {
    public let id: String
    public var authorID: String?
    public var authorName: String
    public var authorInitial: String
    public var authorAvatarURL: String?
    /// userID → username, for resolving <@ID> mentions in content
    public var mentions: [String: String]
    /// channelID → channelName, for resolving <#ID> mentions in content
    public var channelMentions: [String: String]
    public var content: String
    public var attachments: [Attachment]
    public var reactions: [Reaction]
    public var timestamp: Date
    public var isEdited: Bool

    public init(id: String, authorName: String, content: String,
                authorID: String? = nil, authorAvatarURL: String? = nil,
                mentions: [String: String] = [:], channelMentions: [String: String] = [:],
                attachments: [Attachment] = [], reactions: [Reaction] = [],
                timestamp: Date = .now, isEdited: Bool = false) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.authorInitial = String(authorName.prefix(1)).uppercased()
        self.authorAvatarURL = authorAvatarURL
        self.mentions = mentions
        self.channelMentions = channelMentions
        self.content = content
        self.attachments = attachments
        self.reactions = reactions
        self.timestamp = timestamp
        self.isEdited = isEdited
    }
}
