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
        case text, voice, announcement, forum, stage

        public var symbol: String {
            switch self {
            case .text:         return "number"
            case .voice:        return "speaker.wave.2"
            case .announcement: return "megaphone"
            case .forum:        return "list.bullet.rectangle"
            case .stage:        return "person.wave.2"
            }
        }
    }

    public let id: String
    public var name: String
    public var kind: Kind
    public var position: Int
    public var unreadCount: Int

    public init(id: String, name: String, kind: Kind = .text, position: Int = 0, unreadCount: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.position = position
        self.unreadCount = unreadCount
    }
}

public struct Message: Identifiable, Sendable {
    public let id: String
    public var authorName: String
    public var authorInitial: String
    public var content: String
    public var timestamp: Date
    public var isEdited: Bool

    public init(id: String, authorName: String, content: String,
                timestamp: Date = .now, isEdited: Bool = false) {
        self.id = id
        self.authorName = authorName
        self.authorInitial = String(authorName.prefix(1)).uppercased()
        self.content = content
        self.timestamp = timestamp
        self.isEdited = isEdited
    }
}
