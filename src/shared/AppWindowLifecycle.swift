import AppKit
import SwiftUI

@MainActor
class MainWindowAppDelegate: NSObject, NSApplicationDelegate {
    let mainWindows = NSHashTable<NSWindow>.weakObjects()
    var openMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = mainWindows.allObjects.first(where: { $0.isVisible || $0.isMiniaturized }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        return false
    }
}

struct MainWindowContent<Content: View>: View {
    @Environment(\.openWindow) private var openWindow
    let id: String
    let delegate: MainWindowAppDelegate
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(MainWindowRegistration(delegate: delegate))
            .onAppear {
                let id = id
                delegate.openMainWindow = { [openWindow] in openWindow(id: id) }
            }
    }
}

private struct MainWindowRegistration: NSViewRepresentable {
    let delegate: MainWindowAppDelegate

    final class RegistrationView: NSView {
        weak var delegate: MainWindowAppDelegate?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { delegate?.mainWindows.add(window) }
        }
    }

    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView()
        view.delegate = delegate
        return view
    }
    func updateNSView(_ view: RegistrationView, context: Context) {}
}

struct MenuSettings<Content: View>: Scene {
    @ViewBuilder var content: Content

    var body: some Scene { settingsScene() }

    private func settingsScene() -> some Scene {
        let settings = Settings { content.background(NonRestoringSettingsWindow()) }
        // SceneBuilder has no availability else branch; keep both variants on macOS 13.
        if #available(macOS 15.0, *) {
            return SceneBuilder.buildOptional(
                SceneBuilder.buildLimitedAvailability(
                    settings.defaultLaunchBehavior(.suppressed).restorationBehavior(.disabled)
                ))
        } else {
            return SceneBuilder.buildOptional(SceneBuilder.buildLimitedAvailability(settings))
        }
    }
}

private struct NonRestoringSettingsWindow: NSViewRepresentable {
    final class SettingsView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isRestorable = false
        }
    }
    func makeNSView(context: Context) -> SettingsView { SettingsView() }
    func updateNSView(_ view: SettingsView, context: Context) {}
}
