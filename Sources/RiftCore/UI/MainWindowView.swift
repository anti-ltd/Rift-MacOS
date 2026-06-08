import SwiftUI
import AVKit
import UniformTypeIdentifiers
import iUX_MacOS

// MARK: - Pending attachment (pre-send file)

struct PendingAttachment: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let data: Data
    let mimeType: String

    init(filename: String, data: Data, mimeType: String) {
        self.id = UUID()
        self.filename = filename
        self.data = data
        self.mimeType = mimeType
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
}

// Root of the Rift chat window. Shows the chat interface when connected,
// or a login prompt when no session token is configured.
public struct MainWindowView: View {
    @Bindable var model: RiftModel

    public init(model: RiftModel) { self.model = model }

    public var body: some View {
        Group {
            if model.session.hasToken {
                ChatView(model: model)
            } else {
                NoTokenView()
            }
        }

    }
}

// MARK: - Chat layout

// Two-column layout: server+channel sidebar on the left, message pane on the right.
// The sidebar header shows the selected guild name; the channel list lives below it.
struct ChatView: View {
    @Bindable var model: RiftModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarColumn(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            if let channel = model.selectedChannel {
                MessagePaneView(channel: channel, session: model.session,
                                guildChannels: model.selectedGuild?.channels ?? [])
                    .navigationTitle("#\(channel.name)")
            } else {
                ContentUnavailableView(
                    "No channel selected",
                    systemImage: "number",
                    description: Text("Pick a channel from the sidebar.")
                )
            }
        }
    }
}

// MARK: - Sidebar (guild selector + channel list)

private struct SidebarColumn: View {
    @Bindable var model: RiftModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.session.guilds.isEmpty {
                GuildSelectorView(
                    guilds: model.session.guilds,
                    selected: $model.selectedGuild
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }

            if let guild = model.selectedGuild {
                ChannelListView(guild: guild, selected: $model.selectedChannel)
            } else if model.session.state.isConnected && !model.session.directMessages.isEmpty {
                dmList
            } else if model.session.state.isConnected {
                ContentUnavailableView("No server selected", systemImage: "server.rack")
                    .frame(maxHeight: .infinity)
            } else {
                connectionStatusView
            }
        }
        .navigationTitle(model.selectedGuild?.name ?? "Rift")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                connectionIndicator
            }
        }
    }

    private var dmList: some View {
        List(selection: $model.selectedChannel) {
            Section("Direct Messages") {
                ForEach(model.session.directMessages) { dm in
                    HStack {
                        Label(dm.name, systemImage: "bubble.left")
                        Spacer()
                        if dm.unreadCount > 0 {
                            Text("\(dm.unreadCount)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .tag(dm)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            switch model.session.state {
            case .connecting:
                ProgressView()
                Text("Connecting…").foregroundStyle(.secondary)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await model.session.connect() }
                }
            case .disconnected:
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Disconnected")
                    .foregroundStyle(.secondary)
                Button("Connect") {
                    Task { await model.session.connect() }
                }
            case .connected:
                EmptyView()
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch model.session.state {
        case .connected:
            EmptyView()
        case .connecting:
            ProgressView().scaleEffect(0.7)
                .help("Connecting…")
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .help("Connection error")
        case .disconnected:
            Image(systemName: "circle.slash")
                .foregroundStyle(.secondary)
                .help("Disconnected")
        }
    }
}

// MARK: - Guild selector

private struct GuildSelectorView: View {
    let guilds: [Guild]
    @Binding var selected: Guild?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // DMs home button
                Button { selected = nil } label: {
                    ZStack {
                        Circle()
                            .fill(selected == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            .frame(width: 36, height: 36)
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(selected == nil ? .white : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Direct Messages")

                Divider().frame(height: 24)

                ForEach(guilds) { guild in
                    GuildIconButton(guild: guild, isSelected: selected?.id == guild.id) {
                        selected = guild
                    }
                }
            }
        }
    }
}

private struct GuildIconButton: View {
    let guild: Guild
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .frame(width: 36, height: 36)
                if let urlStr = guild.iconURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        } else {
                            Text(guild.initial)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                    }
                } else {
                    Text(guild.initial)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .help(guild.name)
    }
}

// MARK: - Channel list

struct ChannelListView: View {
    let guild: Guild
    @Binding var selected: Channel?

    private var categories: [Channel] {
        guild.channels.filter(\.isCategory).sorted { $0.position < $1.position }
    }

    private func channels(parentID: String?) -> [Channel] {
        guild.channels
            .filter { !$0.isCategory && !$0.isThread && $0.parentID == parentID }
            .sorted { $0.position < $1.position }
    }

    private func threads(parentID: String) -> [Channel] {
        guild.channels
            .filter { $0.isThread && $0.parentID == parentID }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        List(selection: $selected) {
            let uncategorized = channels(parentID: nil)
            if !uncategorized.isEmpty {
                Section {
                    ForEach(uncategorized) { ch in channelRow(ch) }
                }
            }
            ForEach(categories) { cat in
                Section(cat.name.uppercased()) {
                    ForEach(channels(parentID: cat.id)) { ch in
                        channelRow(ch)
                        ForEach(threads(parentID: ch.id)) { thread in
                            threadRow(thread)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func channelRow(_ channel: Channel) -> some View {
        ChannelRow(channel: channel).tag(channel)
    }

    @ViewBuilder
    private func threadRow(_ thread: Channel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 14)
            Image(systemName: thread.kind.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(thread.name)
                .font(.callout)
                .lineLimit(1)
            Spacer()
        }
        .tag(thread)
    }
}

private struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: channel.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(channel.name)
                .lineLimit(1)
            Spacer()
            if channel.unreadCount > 0 {
                Text("\(channel.unreadCount)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Message pane

struct MessagePaneView: View {
    let channel: Channel
    @Bindable var session: DiscordSession
    var guildChannels: [Channel] = []
    @State private var history: [Message] = []
    @State private var draft = ""
    @State private var pendingFiles: [PendingAttachment] = []
    @State private var loadError: String?
    @State private var sending = false

    // Combine fetched history with live gateway messages, deduplicating by id
    private var allMessages: [Message] {
        let live = session.liveMessages[channel.id] ?? []
        let historyIDs = Set(history.map(\.id))
        return history + live.filter { !historyIDs.contains($0.id) }
    }

    // Unique users seen in this channel, for @mention autocomplete
    private var knownUsers: [(id: String, name: String, avatarURL: String?)] {
        var seen = Set<String>()
        var users: [(id: String, name: String, avatarURL: String?)] = []
        for msg in allMessages {
            guard let id = msg.authorID, !seen.contains(id) else { continue }
            seen.insert(id)
            users.append((id: id, name: msg.authorName, avatarURL: msg.authorAvatarURL))
        }
        return users.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // Channel name lookup: guild channels take priority, message's mention_channels as fallback
    private var guildChannelLookup: [String: String] {
        Dictionary(uniqueKeysWithValues: guildChannels.filter { !$0.isCategory }.map { ($0.id, $0.name) })
    }

    private func channelLookup(for message: Message) -> [String: String] {
        message.channelMentions.merging(guildChannelLookup) { _, guild in guild }
    }

    // The partial text after the last unspaced @ in the draft
    private var activeMentionQuery: String? {
        guard let atIdx = draft.lastIndex(of: "@") else { return nil }
        let tail = draft[draft.index(after: atIdx)...]
        guard !tail.contains(" "), !tail.contains("\n") else { return nil }
        return String(tail)
    }

    private var mentionSuggestions: [(id: String, name: String, avatarURL: String?)] {
        guard let query = activeMentionQuery else { return [] }
        let all = knownUsers
        if query.isEmpty { return Array(all.prefix(6)) }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(6).map { $0 }
    }

    // The partial text after the last unspaced # in the draft
    private var activeChannelQuery: String? {
        guard activeMentionQuery == nil else { return nil } // @ takes priority
        guard let hashIdx = draft.lastIndex(of: "#") else { return nil }
        let tail = draft[draft.index(after: hashIdx)...]
        guard !tail.contains(" "), !tail.contains("\n") else { return nil }
        return String(tail)
    }

    private var channelSuggestions: [Channel] {
        guard let query = activeChannelQuery else { return [] }
        let textChannels = guildChannels.filter { !$0.isCategory && !$0.isThread }
        if query.isEmpty { return Array(textChannels.prefix(6)) }
        return textChannels.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hidden Cmd+V interceptor: grabs image data from the clipboard;
            // falls back to normal paste for plain text.
            Button("") { handlePaste() }
                .keyboardShortcut("v", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)

            if allMessages.isEmpty {
                emptyChannelView
            } else {
                messageList
            }
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            Divider()
            if !mentionSuggestions.isEmpty {
                mentionAutocomplete
                Divider()
            } else if !channelSuggestions.isEmpty {
                channelAutocomplete
                Divider()
            }
            if !pendingFiles.isEmpty {
                attachmentStrip
                Divider()
            }
            inputBar
        }
        .task(id: channel.id) { await loadMessages() }
    }

    @ViewBuilder
    private var emptyChannelView: some View {
        ContentUnavailableView {
            Label("#\(channel.name)", systemImage: channel.kind.symbol)
        } description: {
            Text("This is the beginning of #\(channel.name).")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(allMessages) { message in
                        MessageRow(message: message,
                                   channelLookup: channelLookup(for: message),
                                   channelID: channel.id,
                                   token: session.token)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: allMessages.count) {
                if let last = allMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var mentionAutocomplete: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(mentionSuggestions, id: \.id) { user in
                Button { insertMention(user) } label: {
                    HStack(spacing: 8) {
                        userAvatar(urlStr: user.avatarURL, initial: String(user.name.prefix(1)).uppercased())
                            .frame(width: 24, height: 24)
                        Text(user.name)
                            .font(.callout)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func userAvatar(urlStr: String?, initial: String) -> some View {
        ZStack {
            Circle().fill(Color(nsColor: .controlBackgroundColor))
            if let urlStr, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill().clipShape(Circle())
                    } else {
                        Text(initial).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(initial).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private func insertMention(_ user: (id: String, name: String, avatarURL: String?)) {
        guard let atIdx = draft.lastIndex(of: "@") else { return }
        draft = String(draft[..<atIdx]) + "<@\(user.id)> "
    }

    private var channelAutocomplete: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(channelSuggestions) { ch in
                Button { insertChannel(ch) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: ch.kind.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(ch.name).font(.callout)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func insertChannel(_ channel: Channel) {
        guard let hashIdx = draft.lastIndex(of: "#") else { return }
        draft = String(draft[..<hashIdx]) + "<#\(channel.id)> "
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingFiles) { file in
                    ZStack(alignment: .topTrailing) {
                        if file.isImage, let img = NSImage(data: file.data) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "doc.fill").foregroundStyle(.secondary)
                                        Text(file.filename)
                                            .font(.system(size: 8))
                                            .lineLimit(2)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding(4)
                                )
                        }
                        Button { pendingFiles.removeAll { $0.id == file.id } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.55))
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func handlePaste() {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) {
            pendingFiles.append(PendingAttachment(filename: "pasted-image.png", data: data, mimeType: "image/png"))
        } else if let tiff = pb.data(forType: .tiff),
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            pendingFiles.append(PendingAttachment(filename: "pasted-image.png", data: png, mimeType: "image/png"))
        } else {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
    }

    private func pickFiles() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.image, .movie, .audio, .pdf, .data]
            guard panel.runModal() == .OK else { return }
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                            ?? "application/octet-stream"
                pendingFiles.append(PendingAttachment(filename: url.lastPathComponent, data: data, mimeType: mime))
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { pickFiles() } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Attach file")

            TextField("Message #\(channel.name)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { Task { await sendMessage() } }
                .disabled(sending)

            let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty
            if canSend {
                Button { Task { await sendMessage() } } label: {
                    Image(systemName: sending ? "ellipsis.circle" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(sending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadMessages() async {
        history = []
        loadError = nil
        do {
            history = try await DiscordREST.fetchMessages(channelID: channel.id, token: session.token)
        } catch {
            loadError = "Couldn't load messages: \(error.localizedDescription)"
        }
    }

    private func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingFiles.isEmpty else { return }
        let filesToSend = pendingFiles
        draft = ""
        pendingFiles = []
        sending = true
        defer { sending = false }
        do {
            let files = filesToSend.map { ($0.filename, $0.data, $0.mimeType) }
            try await DiscordREST.sendMessage(channelID: channel.id, content: text,
                                              token: session.token, files: files)
        } catch {
            draft = text
            pendingFiles = filesToSend
            loadError = "Send failed: \(error.localizedDescription)"
        }
    }
}

private struct MessageRow: View {
    let message: Message
    var channelLookup: [String: String] = [:]
    var channelID: String = ""
    var token: String = ""

    @State private var reactions: [Reaction]
    @State private var isHovered = false
    @State private var showEmojiPicker = false

    init(message: Message, channelLookup: [String: String] = [:],
         channelID: String = "", token: String = "") {
        self.message = message
        self.channelLookup = channelLookup
        self.channelID = channelID
        self.token = token
        _reactions = State(initialValue: message.reactions)
    }

    // Resolve <@ID>, <@!ID>, and <#ID> tokens into highlighted spans.
    static func renderContent(_ content: String, _ mentions: [String: String],
                              _ channelLookup: [String: String] = [:]) -> AttributedString {
        var result = AttributedString()
        var remaining = content[...]
        while !remaining.isEmpty {
            // Find the next token — whichever comes first
            let atRange  = remaining.range(of: "<@")
            let hashRange = remaining.range(of: "<#")
            let nextRange: Range<String.SubSequence.Index>?
            let isChannel: Bool
            switch (atRange, hashRange) {
            case (nil, nil):
                result += AttributedString(String(remaining)); return result
            case (let a?, nil):
                nextRange = a; isChannel = false
            case (nil, let h?):
                nextRange = h; isChannel = true
            case (let a?, let h?):
                if a.lowerBound <= h.lowerBound { nextRange = a; isChannel = false }
                else                            { nextRange = h; isChannel = true }
            }
            guard let tokenRange = nextRange else { break }
            result += AttributedString(String(remaining[..<tokenRange.lowerBound]))
            remaining = remaining[tokenRange.upperBound...]
            if !isChannel && remaining.hasPrefix("!") { remaining = remaining.dropFirst() }
            if let closeRange = remaining.range(of: ">") {
                let idStr = String(remaining[..<closeRange.lowerBound])
                remaining = remaining[closeRange.upperBound...]
                var span: AttributedString
                if isChannel {
                    let name = channelLookup[idStr] ?? idStr
                    span = AttributedString("#\(name)")
                } else {
                    let name = mentions[idStr] ?? idStr
                    span = AttributedString("@\(name)")
                }
                span.foregroundColor = Color.accentColor
                result += span
            }
        }
        return result
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 36, height: 36)
                if let urlStr = message.authorAvatarURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        } else {
                            Text(message.authorInitial)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(message.authorInitial)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.authorName)
                        .font(.subheadline.weight(.semibold))
                    Text(Self.timeFormatter.string(from: message.timestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if message.isEdited {
                        Text("(edited)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !message.content.isEmpty {
                    Text(Self.renderContent(message.content, message.mentions, channelLookup))
                        .font(.body)
                        .textSelection(.enabled)
                }
                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.attachments) { attachment in
                            AttachmentView(attachment: attachment)
                        }
                    }
                    .padding(.top, message.content.isEmpty ? 0 : 2)
                }
                if !reactions.isEmpty || isHovered {
                    reactionBar
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            // Hover reaction button (top-right of row)
            if isHovered {
                Button { showEmojiPicker = true } label: {
                    Image(systemName: "face.smiling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmojiPicker, arrowEdge: .top) {
                    EmojiPickerView { emoji in
                        showEmojiPicker = false
                        Task { await addNewReaction(emoji) }
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .id(message.id)
        .onHover { isHovered = $0 }
    }

    private var reactionBar: some View {
        HStack(spacing: 4) {
            ForEach(reactions) { reaction in
                ReactionPill(reaction: reaction) {
                    Task { await toggleReaction(reaction) }
                }
            }
            if !reactions.isEmpty {
                Button { showEmojiPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 22)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmojiPicker, arrowEdge: .top) {
                    EmojiPickerView { emoji in
                        showEmojiPicker = false
                        Task { await addNewReaction(emoji) }
                    }
                }
            }
        }
    }

    private func toggleReaction(_ reaction: Reaction) async {
        guard !channelID.isEmpty, !token.isEmpty else { return }
        let wasMe = reaction.me
        // Optimistic update
        if let idx = reactions.firstIndex(where: { $0.id == reaction.id }) {
            if wasMe {
                reactions[idx].count -= 1
                reactions[idx].me = false
                if reactions[idx].count <= 0 { reactions.remove(at: idx) }
            } else {
                reactions[idx].count += 1
                reactions[idx].me = true
            }
        }
        do {
            if wasMe {
                try await DiscordREST.removeReaction(channelID: channelID, messageID: message.id,
                                                     emoji: reaction.apiParam, token: token)
            } else {
                try await DiscordREST.addReaction(channelID: channelID, messageID: message.id,
                                                  emoji: reaction.apiParam, token: token)
            }
        } catch {
            reactions = message.reactions // revert on failure
        }
    }

    private func addNewReaction(_ emoji: String) async {
        guard !channelID.isEmpty, !token.isEmpty else { return }
        if let idx = reactions.firstIndex(where: { $0.emojiName == emoji }) {
            if !reactions[idx].me { await toggleReaction(reactions[idx]) }
            return
        }
        reactions.append(Reaction(emojiName: emoji, count: 1, me: true))
        do {
            try await DiscordREST.addReaction(channelID: channelID, messageID: message.id,
                                              emoji: emoji, token: token)
        } catch {
            reactions = message.reactions
        }
    }
}

// MARK: - Reaction views

private struct ReactionPill: View {
    let reaction: Reaction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(reaction.display)
                    .font(.system(size: 14))
                Text("\(reaction.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reaction.me ? Color.accentColor : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                reaction.me
                    ? Color.accentColor.opacity(0.15)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(reaction.me ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmojiPickerView: View {
    let onSelect: (String) -> Void

    private let emojis: [String] = [
        "👍","👎","❤️","😂","😮","😢","🎉","🔥",
        "✅","❌","🙏","👀","💯","🤔","😎","🚀",
        "⭐","💪","🤣","😍","🥺","💀","🤯","🤝",
        "😊","🙌","👏","💥","⚡","🌟","🎯","💎",
    ]
    private let columns = Array(repeating: GridItem(.fixed(38)), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 324)
    }
}

// MARK: - Attachment views

private struct AttachmentView: View {
    let attachment: Attachment

    var body: some View {
        if attachment.isVideo, let url = URL(string: attachment.url) {
            VideoPlayerView(url: url, width: attachment.width, height: attachment.height)
        } else if attachment.isImage, let url = URL(string: attachment.url) {
            if attachment.isAnimated {
                AnimatedImageView(url: url)
                    .frame(maxWidth: 400, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Label("Failed to load image", systemImage: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 200, height: 150)
                            .overlay(ProgressView())
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc.fill").foregroundStyle(.secondary)
                Text(attachment.filename).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// Uses AVPlayerView (AppKit) rather than SwiftUI's VideoPlayer to avoid
// the _AVKit_SwiftUI metadata crash on macOS 26.
private struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    let width: Int?
    let height: Int?

    private var displaySize: CGSize {
        let maxW: CGFloat = 400
        let maxH: CGFloat = 280
        if let w = width, let h = height, w > 0, h > 0 {
            let scale = min(maxW / CGFloat(w), maxH / CGFloat(h), 1)
            return CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        }
        return CGSize(width: maxW, height: 225) // default 16:9
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = AVPlayer(url: url)
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        displaySize
    }
}

private struct AnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: @unchecked Sendable {
        private var task: Task<Void, Never>?

        func load(url: URL, into imageView: NSImageView) {
            task?.cancel()
            task = Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      !Task.isCancelled else { return }
                await MainActor.run { imageView.image = NSImage(data: data) }
            }
        }

        deinit { task?.cancel() }
    }
}

// MARK: - No-token prompt

private struct NoTokenView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Not connected", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Click the Rift icon in the menu bar and enter your token under Account to get started.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
