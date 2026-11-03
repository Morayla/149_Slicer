import AppKit
import SwiftUI

struct GlassSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var label: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject {
        var parent: GlassSlider
        var label = ""
        init(_ parent: GlassSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            let raw = sender.doubleValue
            let v =
                parent.step > 0
                ? parent.range.lowerBound + ((raw - parent.range.lowerBound) / parent.step).rounded() * parent.step
                : raw
            parent.value = min(parent.range.upperBound, max(parent.range.lowerBound, v))
            sender.doubleValue = parent.value
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NeutralSlider()
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.focusRingType = .none
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        if slider.minValue != range.lowerBound { slider.minValue = range.lowerBound }
        if slider.maxValue != range.upperBound { slider.maxValue = range.upperBound }
        if slider.doubleValue != value { slider.doubleValue = value }
        if slider.isEnabled != enabled { slider.isEnabled = enabled }
        let appearance: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if slider.appearance?.name != appearance {
            slider.appearance = NSAppearance(named: appearance)
            slider.trackFillColor = NSColor(white: colorScheme == .dark ? 0.78 : 0.30, alpha: 1)
        }
        let localizedLabel = L(label)
        if context.coordinator.label != localizedLabel {
            slider.setAccessibilityLabel(localizedLabel)
            context.coordinator.label = localizedLabel
        }
        let increment = step > 0 ? step : (range.upperBound - range.lowerBound) / 100
        if slider.altIncrementValue != increment { slider.altIncrementValue = increment }
    }
}


private final class NeutralSlider: NSSlider {
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            NSColor.labelColor.withAlphaComponent(0.35).setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).stroke()
        }
    }
}
