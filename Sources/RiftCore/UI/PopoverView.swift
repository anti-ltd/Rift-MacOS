import AppKit
import SwiftUI
import iUX_MacOS

public struct PopoverView: View {
    @Bindable var model: RiftModel
    @State private var tab: PopoverTab = .account

    public init(model: RiftModel) { self.model = model }

    public var body: some View {
        SettingsPopover(selection: $tab) {
            PopOutButton(windowID: RiftModule.windowID)
        } content: { tab in
            switch tab {
            case .account: AccountTab(session: model.session)
            case .about:   AboutTab()
            }
        }
    }
}

// MARK: - Tabs

enum PopoverTab: String, CaseIterable, Identifiable, SettingsTab {
    case account, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .account: return "Account"
        case .about:   return "About"
        }
    }
    var icon: String {
        switch self {
        case .account: return "person.circle"
        case .about:   return "info.circle"
        }
    }
}

// MARK: - Account Tab

struct AccountTab: View {
    @Bindable var session: DiscordSession
    @State private var tokenDraft = ""
    @State private var showToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: UX.cardSpacing) {
            statusCard
            tokenCard
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        CardSection("Status") {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if session.state.isConnected {
                    Button("Disconnect") { session.disconnect() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                } else if session.hasToken {
                    Button("Reconnect") { session.connect() }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    @ViewBuilder
    private var tokenCard: some View {
        CardSection("Token") {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if showToken {
                        TextField("Paste token…", text: $tokenDraft)
                    } else {
                        SecureField(session.hasToken ? "••••••••••" : "Paste token…", text: $tokenDraft)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                HStack {
                    Button(showToken ? "Hide" : "Show") {
                        showToken.toggle()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if session.hasToken {
                        Button("Clear", role: .destructive) {
                            session.token = ""
                            tokenDraft = ""
                            session.disconnect()
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("Save & Connect") {
                        session.token = tokenDraft
                        tokenDraft = ""
                        showToken = false
                        session.connect()
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .error:        return .red
        case .disconnected: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var statusLabel: String {
        switch session.state {
        case .connected(let u):   return "Connected as \(u)"
        case .connecting:         return "Connecting…"
        case .error(let msg):     return msg
        case .disconnected:       return session.hasToken ? "Disconnected" : "No token configured"
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @State private var updateStatus: String?
    @State private var checking = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        CardSection("About") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rift").font(.headline)
                Text("Version \(version)").foregroundStyle(.secondary)

                #if !RIFT_MAS
                Button(checking ? "Checking…" : "Check for updates") {
                    Task { await checkForUpdates() }
                }
                .disabled(checking)
                if let updateStatus {
                    Text(updateStatus).font(.callout).foregroundStyle(.secondary)
                }
                #endif
            }
        }
    }

    #if !RIFT_MAS
    private func checkForUpdates() async {
        checking = true
        defer { checking = false }
        do {
            let info = try await UpdateChecker.fetch(appID: "rift")
            updateStatus = UpdateChecker.isNewer(info.version, than: version)
                ? "Update available: \(info.version)"
                : "You're up to date."
        } catch {
            updateStatus = "Couldn't check: \(error.localizedDescription)"
        }
    }
    #endif
}

// MARK: - Window opener

@MainActor
public enum RiftWindowOpener {
    public static var action: OpenWindowAction?

    public static func open() {
        guard let action else { NSSound.beep(); return }
        action(id: RiftModule.windowID)
        NSApp.activate(ignoringOtherApps: true)
        let id = RiftModule.windowID
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let raw = window.identifier?.rawValue, raw.contains(id) else { continue }
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
