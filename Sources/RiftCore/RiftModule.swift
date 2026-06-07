import SwiftUI
import iUX_MacOS

@MainActor
public final class RiftModule: AppModule {

    // MARK: - Identity

    public static let moduleID    = "ltd.anti.rift"
    public static let displayName = "Rift"
    public static let symbolName  = "bubble.left.and.bubble.right.fill"
    public static let windowID    = "rift-main"

    // MARK: - Core

    private let model: RiftModel

    public required init() {
        model = RiftModel()
    }

    public func start() {
        model.start()
    }

    public var isMuted: Bool { false }

    // MARK: - UI

    /// Menu-bar popover: account settings + about.
    public func settingsView() -> AnyView {
        AnyView(PopoverView(model: model))
    }

    /// Main Rift window: chat interface (or login prompt if not authenticated).
    public func windowView() -> AnyView {
        AnyView(MainWindowView(model: model))
    }
}
