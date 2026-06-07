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

    private var textChannels: [Channel] { guild.channels.filter { $0.kind == .text || $0.kind == .announcement }.sorted { $0.position < $1.position } }
    private var voiceChannels: [Channel] { guild.channels.filter { $0.kind == .voice || $0.kind == .stage }.sorted { $0.position < $1.position } }

    var body: some View {
        List(selection: $selected) {
            if !textChannels.isEmpty {
                Section("Text Channels") {
                    ForEach(textChannels) { channel in
                        ChannelRow(channel: channel).tag(channel)
                    }
                }
            }
            if !voiceChannels.isEmpty {
                Section("Voice Channels") {
                    ForEach(voiceChannels) { channel in
                        ChannelRow(channel: channel).tag(channel)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
    @State private var messages: [Message] = []
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyChannelView
            } else {
                messageList
            }
            Divider()
            inputBar
        }
        .onAppear { loadMessages() }
        .onChange(of: channel.id) { loadMessages() }
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
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
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
                .onSubmit {
                    sendMessage()
                }

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadMessages() {
        // TODO: fetch channel message history from Discord REST API
        // GET /channels/{channel.id}/messages
        messages = []
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // TODO: POST /channels/{channel.id}/messages via Discord REST API
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
