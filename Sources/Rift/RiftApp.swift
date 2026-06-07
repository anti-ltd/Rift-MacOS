import AppKit
import SwiftUI
import iUX_MacOS
import RiftCore

@main
struct RiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(RiftModule.displayName, id: RiftModule.windowID) {
            appDelegate.module.windowView()
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)

        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let module = RiftModule()
    private var menuBar: MenuBarController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--icon"), idx + 1 < args.count {
            AppIconRenderer.run(directory: args[idx + 1])
            NSApp.terminate(nil)
            return
        }

        menuBar = MenuBarController(
            symbolName: RiftModule.symbolName,
            accessibilityLabel: RiftModule.displayName,
            popoverSize: NSSize(width: 460, height: 400),
            rootView: module.settingsView(),
            clickStyle: .leftClickMenu,
            menuProvider: { [weak self] in self?.contextMenu() }
        )
        module.start()

        // Close the SwiftUI Window that auto-opens at launch for LSUIElement apps
        let id = RiftModule.windowID
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue.contains(id) == true {
                window.close()
            }
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Rift", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        open.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil)
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Rift", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)

        return menu
    }

    @objc private func menuOpen() { RiftWindowOpener.open() }
    @objc private func menuSettings() { RiftWindowOpener.open() }
    @objc private func menuQuit() { NSApplication.shared.terminate(nil) }
}
