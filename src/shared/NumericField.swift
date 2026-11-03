import AppKit
import SwiftUI

private struct NumericScrubKey: EnvironmentKey { static let defaultValue: (Bool) -> Void = { _ in } }
extension EnvironmentValues {
    var numericScrubChanged: (Bool) -> Void {
        get { self[NumericScrubKey.self] }
        set { self[NumericScrubKey.self] = newValue }
    }
}
struct NumericField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var step: Double = 0.1
    var integral = false
    var minimum: Double?
    var maximum: Double?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.numericScrubChanged) private var scrubChanged

    init(_ title: String, text: Binding<String>, step: Double = 0.1, integral: Bool = false, minimum: Double? = nil, maximum: Double? = nil) {
        self.title = title
        _text = text
        self.step = step
        self.integral = integral
        self.minimum = minimum; self.maximum = maximum
    }

    init(_ title: String, value: Binding<Double>, step: Double = 0.1) {
        self.init(
            title,
            text: Binding(
                get: { Self.format(value.wrappedValue) },
                set: { if let number = Double($0), number.isFinite { value.wrappedValue = number } }
            ), step: step)
    }

    init(_ title: String, value: Binding<Int>) {
        self.init(
            title,
            text: Binding(
                get: { String(value.wrappedValue) },
                set: { if let number = Int($0) { value.wrappedValue = number } }
            ), step: 1, integral: true)
    }

    static func format(_ number: Double) -> String {
        number.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never).precision(.fractionLength(0...6)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ScrubbableTextField {
        let field = ScrubbableTextField()
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate = context.coordinator
        field.toolTip = L("拖动调整；按住选择步长；单击输入。中键可直接打开步长。")
        return field
    }
    func updateNSView(_ field: ScrubbableTextField, context: Context) {
        context.coordinator.owner = self
        field.isEnabled = isEnabled
        field.step = step
        field.integral = integral
        field.minimum = minimum; field.maximum = maximum
        field.setAccessibilityLabel(L(title))
        field.setAccessibilityIdentifier("number." + title)
        field.changed = { text = $0 }
        field.trackingChanged = scrubChanged
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: NumericField
        init(_ owner: NumericField) { self.owner = owner }
        func controlTextDidChange(_ notification: Notification) {
            owner.text = (notification.object as! NSTextField).stringValue
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            (notification.object as! NSTextField).stringValue = owner.text
        }
    }
}

final class ScrubbableTextField: NSTextField {
    var step = 0.1
    var integral = false
    var minimum: Double?
    var maximum: Double?
    var changed: ((String) -> Void)?
    var trackingChanged: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) { trackValue(event, ladderImmediately: false) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            trackValue(event, ladderImmediately: true)
        } else {
            super.otherMouseDown(with: event)
        }
    }
    private func trackValue(_ event: NSEvent, ladderImmediately: Bool) {
        guard isEnabled, let window else { return }
        if event.clickCount > 1 && !ladderImmediately {
            super.mouseDown(with: event)
            return
        }
        guard let initial = Double(stringValue), initial.isFinite else {
            window.makeFirstResponder(self)
            selectText(nil)
            return
        }
        var origin = event.locationInWindow.x
        var base = initial
        var dragging = false
        var ladder: ValueLadderPanel?
        var selectedStep = step
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDragged, .leftMouseUp, .otherMouseDragged, .otherMouseUp, .keyDown,
        ]
        let deadline = Date(timeIntervalSinceNow: ladderImmediately ? 0 : 0.35)
        func apply(_ value: Double) {
            let formatted = NumericField.format(value)
            if formatted != stringValue {
                stringValue = formatted
                changed?(formatted)
            }
        }
        defer {
            if let ladder {
                window.removeChildWindow(ladder)
                ladder.orderOut(nil)
            }
            if dragging {
                NSCursor.pop()
                trackingChanged?(false)
            }
        }
        while true {
            let received = window.nextEvent(
                matching: mask, until: dragging ? .distantFuture : deadline, inMode: .eventTracking, dequeue: true)
            if received == nil {
                window.makeFirstResponder(nil)
                let panel = ValueLadderPanel(
                    at: window.convertPoint(toScreen: event.locationInWindow),
                    field: window.convertToScreen(convert(bounds, to: nil)), step: step, integral: integral)
                window.addChildWindow(panel, ordered: .above)
                panel.orderFront(nil)
                panel.displayIfNeeded()
                ladder = panel
                dragging = true
                trackingChanged?(true)
                NSCursor.resizeLeftRight.push()
                continue
            }
            let next = received!
            if next.type == .leftMouseUp || next.type == .otherMouseUp {
                if !dragging {
                    window.makeFirstResponder(self)
                    selectText(nil)
                }
                break
            }
            if next.type == .keyDown {
                if next.keyCode == 53 {
                    apply(initial)
                    break
                }
                continue
            }
            if let ladder, let quantum = ladder.select(at: window.convertPoint(toScreen: next.locationInWindow)),
                quantum != selectedStep
            {
                selectedStep = quantum
                base = Double(stringValue) ?? initial
                origin = next.locationInWindow.x
            }
            let delta = next.locationInWindow.x - origin
            if !dragging {
                guard abs(delta) >= 3 else { continue }
                window.makeFirstResponder(nil)
                dragging = true
                trackingChanged?(true)
                NSCursor.resizeLeftRight.push()
            }
            let multiplier =
                next.modifierFlags.contains(.shift) ? 10.0 : next.modifierFlags.contains(.option) ? 0.1 : 1.0
            let quantum = integral ? max(1, selectedStep * multiplier) : selectedStep * multiplier
            let value = base + (delta / 3).rounded(.towardZero) * quantum
            let bounded = min(maximum ?? .greatestFiniteMagnitude, max(minimum ?? -.greatestFiniteMagnitude, value))
            apply(integral ? bounded.rounded() : bounded)
        }
    }
}

private final class ValueLadderPanel: NSPanel {
    let ladder: ValueLadderView
    let originY: CGFloat
    let initialSelection: Int
    init(at point: NSPoint, field: NSRect, step: Double, integral: Bool) {
        let values: [Double] = integral ? [100, 10, 1] : [100, 10, 1, 0.1, 0.01, 0.001]
        let selected = values.indices.min { abs(log10(values[$0] / step)) < abs(log10(values[$1] / step)) }!
        originY = point.y
        initialSelection = selected
        ladder = ValueLadderView(values: values, selected: selected)
        let size = NSSize(width: 104, height: CGFloat(values.count) * 28 + 12)
        var frame = NSRect(
            x: field.maxX + 12, y: point.y - size.height + CGFloat(selected) * 28 + 20, width: size.width,
            height: size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            if frame.maxX > screen.visibleFrame.maxX { frame.origin.x = field.minX - size.width - 12 }
            frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
        }
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .popUpMenu
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 9
        background.layer?.masksToBounds = true
        contentView = background
        ladder.frame = background.bounds
        ladder.autoresizingMask = [.width, .height]
        background.addSubview(ladder)
    }
    func select(at point: NSPoint) -> Double? {
        let index = min(ladder.values.count - 1, max(0, initialSelection - Int(((point.y - originY) / 28).rounded())))
        ladder.selected = index
        ladder.needsDisplay = true
        ladder.displayIfNeeded()
        return ladder.values[index]
    }
}

private final class ValueLadderView: NSView {
    let values: [Double]
    var selected: Int
    init(values: [Double], selected: Int) {
        self.values = values
        self.selected = selected
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, value) in values.enumerated() {
            let rect = NSRect(
                x: 6, y: bounds.height - CGFloat(index + 1) * 28 - 6, width: bounds.width - 12, height: 28)
            if index == selected {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let title = NumericField.format(value) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: index == selected ? NSColor.white : NSColor.labelColor,
            ]
            let size = title.size(withAttributes: attributes)
            title.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
