import SceneKit
import SwiftUI

struct AppSettings: View {
    @AppStorage("interfaceLanguage") private var language = "zh-Hans"
    @AppStorage("previewQuality") private var quality = "detailed"

    var body: some View {
        Form {
            Section {
                Picker(L("语言"), selection: $language) {
                    uiText("简体中文").tag("zh-Hans")
                    uiText("English").tag("en")
                }
                uiText("语言更改在重新打开应用后生效。").font(.caption).foregroundStyle(.secondary)
            }
            Section(L("三维预览")) {
                Picker(L("画质"), selection: $quality) {
                    uiText("精细").tag("detailed")
                    uiText("流畅").tag("balanced")
                }
                uiText("流畅模式降低边缘采样，保留完整几何和打印纹路。").font(.caption).foregroundStyle(.secondary)
            }
            uiText("深浅色跟随系统。").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 310)
        .onChange(of: language) { UserDefaults.standard.set([$0], forKey: "AppleLanguages") }
    }
}

enum PreviewQuality {
    static func apply(to view: SCNView) {
        let mode: SCNAntialiasingMode =
            UserDefaults.standard.string(forKey: "previewQuality") == "balanced" ? .multisampling2X : .multisampling4X
        if view.antialiasingMode != mode { view.antialiasingMode = mode }
        view.preferredFramesPerSecond = 60
    }
}
