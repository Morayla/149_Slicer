import SceneKit
import SwiftUI

struct AppSettings: View {
    @AppStorage("interfaceLanguage") private var language = "zh-Hans"

    var body: some View {
        Form {
            Picker(L("语言"), selection: $language) {
                uiText("简体中文").tag("zh-Hans")
                uiText("English").tag("en")
            }
            uiText("语言更改在重新打开应用后生效。").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 150)
        .onChange(of: language) { UserDefaults.standard.set([$0], forKey: "AppleLanguages") }
    }
}

enum PreviewQuality {
    static func apply(to view: SCNView) {
        if view.antialiasingMode != .multisampling4X { view.antialiasingMode = .multisampling4X }
        if view.preferredFramesPerSecond != 60 { view.preferredFramesPerSecond = 60 }
    }
}
