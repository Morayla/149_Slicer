import AppKit
import SwiftUI

enum ParameterLayout {
    static let valueWidth: CGFloat = 116
}
struct ParameterOption: Equatable {
    let title: String, value: String
    let enabled: Bool
    init(_ title: String, _ value: String, enabled: Bool = true, localize: Bool = true) {
        self.title = localize ? L(title) : title
        self.value = value
        self.enabled = enabled
    }
}
struct ParameterPicker: View {
    let title: String
    @Binding var selection: String
    let options: [ParameterOption]
    init(_ title: String, selection: Binding<String>, options: [ParameterOption]) {
        self.title = title
        _selection = selection
        self.options = options
    }
    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: L(title)).frame(maxWidth: .infinity, alignment: .leading)
            ParameterPopup(title: title, selection: $selection, options: options)
                .frame(width: ParameterLayout.valueWidth, height: 24)
            Color.clear.frame(width: WorkspaceLayout.unitWidth, height: 1)
        }.frame(minHeight: WorkspaceLayout.rowHeight)
    }
}
private struct ParameterPopup: NSViewRepresentable {
    let title: String
    @Binding var selection: String
    let options: [ParameterOption]
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject {
        var parent: ParameterPopup
        var options: [ParameterOption] = []
        init(_ parent: ParameterPopup) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard options.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = options[sender.indexOfSelectedItem].value
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if options != context.coordinator.options {
            context.coordinator.options = options
            button.removeAllItems()
            button.menu?.autoenablesItems = false
            for option in options {
                button.addItem(withTitle: option.title)
                button.lastItem?.isEnabled = option.enabled
            }
        }
        button.selectItem(at: options.firstIndex { $0.value == selection } ?? -1)
        button.isEnabled = enabled
        button.toolTip = button.title
        button.setAccessibilityLabel(L(title))
    }
}
