import AppKit
import SwiftUI

struct WindowGlass: NSViewRepresentable {
    final class Backdrop: NSView {
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.appearance = nil
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .line
            window.toolbarStyle = .unifiedCompact
        }
    }
    func makeNSView(context: Context) -> Backdrop { Backdrop() }
    func updateNSView(_ view: Backdrop, context: Context) {}
}
struct GlassCard: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
                    Color.primary.opacity(0.08), lineWidth: 0.6))
    }
}
extension View { func glassCard(_ radius: CGFloat = 18) -> some View { modifier(GlassCard(radius: radius)) } }

struct CapsuleSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) {
            configuration.label.frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(.switch).controlSize(.small).frame(minHeight: 30)
    }
}
struct NeutralSegments<T: Hashable>: View {

    let titles: [String]
    let values: [T]
    @Binding var selection: T
    var disabledValues: Set<T> = []
    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { i in
                Button {
                    selection = values[i]
                } label: {
                    uiText(titles[i]).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
                        .background(
                            selection == values[i] ? Color.primary.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).foregroundStyle(selection == values[i] ? .primary : .secondary)
                    .disabled(disabledValues.contains(values[i])).opacity(disabledValues.contains(values[i]) ? 0.4 : 1)
                    .help(L(titles[i])).accessibilityValue(L(selection == values[i] ? "已选中" : "未选中"))
            }
        }.padding(3).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}
