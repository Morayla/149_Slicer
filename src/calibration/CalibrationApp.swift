import SwiftUI

#if !TESTING
    @main
    struct CalibrationApp: App {
        @StateObject private var store = CalibrationStore()
        @NSApplicationDelegateAdaptor(CalibrationAppDelegate.self) private var delegate

        var body: some Scene {
            Window("149 Calibration", id: "calibration") {
                MainWindowContent(id: "calibration", delegate: delegate) {
                    CalibrationWorkspace(store: store)
                }
                .onAppear { delegate.store = store }
                .background(WindowGlass())
                .frame(minWidth: 1000, minHeight: 680)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
                    _ in
                    store.setActive(false)
                }
            }
            .defaultSize(width: 1280, height: 800)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button(L("打开测量记录…"), action: store.open).keyboardShortcut("o").disabled(store.busy)
                    Button(L("保存测量记录")) { store.save() }.keyboardShortcut("s")
                    Button(L("另存为…")) { store.save(asNew: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
                    Divider()
                    Button(L("导出 CSV…"), action: store.exportCSV).keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
            MenuSettings { CalibrationSettings(store: store) }
        }
    }
#endif

final class CalibrationAppDelegate: MainWindowAppDelegate {
    weak var store: CalibrationStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.ownsMotion else { return .terminateNow }
        store.stopBeforeQuitting { stopped in sender.reply(toApplicationShouldTerminate: stopped) }
        return .terminateLater
    }
}
