import SwiftUI

private let interfaceBundle: Bundle? = {
    let language = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "zh-Hans"
    guard language == "en" else { return nil }
    return Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
}()
func L(_ text: String) -> String { interfaceBundle?.localizedString(forKey: text, value: text, table: nil) ?? text }
func uiText(_ text: String) -> Text { Text(verbatim: L(text)) }

extension View {
    func interfaceFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        font(weight.map { Font.system(style).weight($0) } ?? .system(style))
    }
    func interfaceFixedFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight))
    }
}

func LF(_ key: String, _ arguments: String...) -> String { String(format: L(key), arguments: arguments.map { L($0) }) }
