import SwiftUI
import iUX_MacOS

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
        .background(RiftWindowOpenerBridge())
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
                MessagePaneView(channel: channel, session: model.session)
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
                    Label(dm.name, systemImage: "bubble.left")
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
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Connected")
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
                Text(guild.initial)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
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
    @State private var history: [Message] = []
    @State private var draft = ""
    @State private var loadError: String?
    @State private var sending = false

    // Combine fetched history with live gateway messages, deduplicating by id
    private var allMessages: [Message] {
        let live = session.liveMessages[channel.id] ?? []
        let historyIDs = Set(history.map(\.id))
        return history + live.filter { !historyIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        MessageRow(message: message)
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

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message #\(channel.name)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { Task { await sendMessage() } }
                .disabled(sending)

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        guard !text.isEmpty else { return }
        draft = ""
        sending = true
        defer { sending = false }
        do {
            try await DiscordREST.sendMessage(channelID: channel.id, content: text, token: session.token)
        } catch {
            draft = text // restore on failure
            loadError = "Send failed: \(error.localizedDescription)"
        }
    }
}

private struct MessageRow: View {
    let message: Message

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
                Text(message.authorInitial)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
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
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .id(message.id)
    }
}

// MARK: - Window opener bridge

// Captures SwiftUI's openWindow action at render time so AppKit menu items
// can open the Rift window. Must live inside the Window scene's view tree
// (not the popover) so it fires on app launch before the window is closed.
struct RiftWindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { RiftWindowOpener.action = openWindow }
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
