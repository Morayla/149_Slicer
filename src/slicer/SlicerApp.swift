import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if !TESTING
    @main
    struct SlicerApp: App {
        @NSApplicationDelegateAdaptor(MainWindowAppDelegate.self) private var delegate

        init() {
            UserDefaults.standard.removeObject(forKey: "AppleAccentColor")
            UserDefaults.standard.removeObject(forKey: "AppleHighlightColor")
            NSApplication.shared.appearance = nil
            DispatchQueue.main.async {
                if let url = Bundle.main.url(forResource: "149", withExtension: "icns") {
                    NSApp.applicationIconImage = NSImage(contentsOf: url)
                }
            }
        }
        var body: some Scene {
            WindowGroup("149 Slicer", id: "slicer") {
                MainWindowContent(id: "slicer", delegate: delegate) { ContentView() }
            }.windowStyle(.titleBar).commands {
                ProjectCommands()
                WorkspaceCommands()
            }
            MenuSettings { AppSettings() }
            Window(L("打印机控制"), id: "printer") { PrinterWindow() }.defaultSize(width: 1100, height: 780)
            Window(L("颗粒烘干机"), id: "pellet-dryer") { PelletDryerWindow() }.defaultSize(width: 1000, height: 780)
            Window(L("打印监控"), id: "camera-monitor") { CameraMonitorWindow() }.defaultSize(width: 1100, height: 800)
            Window(L("AMS-HT 烘干机"), id: "ams-ht") { AMSDryingWindow() }.defaultSize(width: 1080, height: 650)
        }
    }
#endif
