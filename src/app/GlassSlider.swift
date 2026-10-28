import SwiftUI
import AppKit

struct GlassSlider:NSViewRepresentable {
    @Binding var value:Double
    let range:ClosedRange<Double>
    var step:Double=0
    var label:String=""
    @Environment(\.isEnabled) private var enabled
    final class Coordinator:NSObject {
        var parent:GlassSlider
        init(_ parent:GlassSlider){self.parent=parent}
        @objc func changed(_ sender:NSSlider) {
            let raw=sender.doubleValue
            let v=parent.step>0 ? parent.range.lowerBound+((raw-parent.range.lowerBound)/parent.step).rounded()*parent.step:raw
            parent.value=min(parent.range.upperBound,max(parent.range.lowerBound,v));sender.doubleValue=parent.value
        }
    }
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSSlider {
        let slider=NSSlider();slider.isContinuous=true
        slider.target=context.coordinator;slider.action=#selector(Coordinator.changed(_:))
        slider.focusRingType = .default
        slider.setContentHuggingPriority(.defaultLow,for:.horizontal)
        return slider
    }
    func updateNSView(_ slider:NSSlider,context:Context) {
        context.coordinator.parent=self;slider.minValue=range.lowerBound;slider.maxValue=range.upperBound
        slider.doubleValue=value;slider.isEnabled=enabled;slider.setAccessibilityLabel(L(label))
        slider.altIncrementValue=step>0 ? step:(range.upperBound-range.lowerBound)/100
        slider.needsDisplay=true
    }
}
