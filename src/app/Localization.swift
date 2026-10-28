import SwiftUI
import Foundation

final class AppLanguage:ObservableObject {
    static let shared=AppLanguage()
    let code="zh-Hans"
    let english=false
}
func L(_ text:String)->String {text}
func uiText(_ text:String)->Text {Text(verbatim:text)}

// Keep the original system typography; no app-specific font preference.
final class AppTypography:ObservableObject {
    static let shared=AppTypography()
    let preset="classic"
    static func font(_ style:Font.TextStyle,weight:Font.Weight?=nil)->Font {weight.map{Font.system(style).weight($0)} ?? .system(style)}
    static func fixedFont(size:CGFloat,weight:Font.Weight = .regular)->Font {.system(size:size,weight:weight)}
}
private struct InterfaceFontModifier:ViewModifier {
    @ObservedObject var typography=AppTypography.shared
    let style:Font.TextStyle?;let size:CGFloat?;let weight:Font.Weight?
    func body(content:Content)->some View {
        content.font(style.map{AppTypography.font($0,weight:weight)} ?? AppTypography.fixedFont(size:size ?? 13,weight:weight ?? .regular))
    }
}
extension View {
    func interfaceFont(_ style:Font.TextStyle,weight:Font.Weight?=nil)->some View {modifier(InterfaceFontModifier(style:style,size:nil,weight:weight))}
    func interfaceFixedFont(size:CGFloat,weight:Font.Weight = .regular)->some View {modifier(InterfaceFontModifier(style:nil,size:size,weight:weight))}
}
