import SwiftUI
import AppKit

struct WindowGlass:NSViewRepresentable {
    final class Backdrop:NSView {
        override var isOpaque:Bool {true}
        override func draw(_ dirtyRect:NSRect) {NSColor.windowBackgroundColor.setFill();dirtyRect.fill()}
        override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsDisplay=true}
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window=window else{return}
            window.isOpaque=true
            window.backgroundColor = .windowBackgroundColor
            window.appearance=nil
            window.titlebarAppearsTransparent=false
            window.titlebarSeparatorStyle = .line
            window.toolbarStyle = .unifiedCompact
        }
    }
    func makeNSView(context:Context)->Backdrop {Backdrop()}
    func updateNSView(_ view:Backdrop,context:Context) {}
}
struct GlassCard:ViewModifier {
    var radius:CGFloat=18
    func body(content:Content)->some View {
        content.background(.regularMaterial,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(Color.primary.opacity(0.08),lineWidth:0.6))
    }
}
extension View {func glassCard(_ radius:CGFloat=18)->some View {modifier(GlassCard(radius:radius))}}

// Monitor only scrolling over this canvas; leave parameter scrolling intact.
struct CanvasScrollZoom:NSViewRepresentable {
    let changed:(Double)->Void
    final class Surface:NSView {
        var changed:((Double)->Void)?;var monitor:Any?
        override func viewDidMoveToWindow() {
            if let monitor=monitor {NSEvent.removeMonitor(monitor);self.monitor=nil}
            guard window != nil else{return}
            monitor=NSEvent.addLocalMonitorForEvents(matching:.scrollWheel){[weak self] event in
                guard let self=self,event.window===self.window,self.bounds.contains(self.convert(event.locationInWindow,from:nil)) else{return event}
                self.changed?(exp(Double(event.scrollingDeltaY)*0.012));return nil
            }
        }
        deinit {if let monitor=monitor {NSEvent.removeMonitor(monitor)}}
    }
    func makeNSView(context:Context)->Surface {let v=Surface();v.changed=changed;return v}
    func updateNSView(_ view:Surface,context:Context) {view.changed=changed}
}

// Shared multi-hue, ordered scale for quantitative analysis; never used for glass.
func previewMetricRGB(_ fraction:Double)->[Double] {
    let stops:[[Double]]=[[0.36,0.38,0.93],[0.20,0.68,0.94],[0.24,0.79,0.62],[0.98,0.78,0.28],[1.0,0.38,0.34]]
    let scaled=min(1,max(0,fraction))*Double(stops.count-1)
    let i=min(stops.count-2,Int(scaled)),t=scaled-Double(i)
    return zip(stops[i],stops[i+1]).map {$0+($1-$0)*t}
}
let previewRoleRGB:[[Double]]=[[0.64,0.67,0.72],[0.30,0.76,0.71],[0.32,0.60,1.0],[0.82,0.50,0.94],[0.55,0.58,0.64]]
let previewRoleColors:[Color]=previewRoleRGB.map {Color(red:$0[0],green:$0[1],blue:$0[2])}

// Inherit the surrounding glass card instead of tinting the preview blue.
struct PreviewGlassBackground:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    var body:some View {Color.clear}
}

struct CapsuleSwitchStyle:ToggleStyle {
    func makeBody(configuration:Configuration)->some View {
        Toggle(isOn:configuration.$isOn) {
            configuration.label.frame(maxWidth:.infinity,alignment:.leading)
        }.toggleStyle(.switch).controlSize(.small).frame(minHeight:30)
    }
}
struct NeutralSegments<T:Hashable>:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    let titles:[String];let values:[T]
    @Binding var selection:T
    var disabledValues:Set<T>=[]
    var body:some View {
        HStack(spacing:2) {
            ForEach(titles.indices,id:\.self) {i in
                Button {selection=values[i]} label:{
                    uiText(titles[i]).font(.system(size:12,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth:.infinity,minHeight:28).contentShape(Rectangle())
                        .background(selection==values[i] ? Color.primary.opacity(0.12):.clear,in:RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).foregroundStyle(selection==values[i] ? .primary:.secondary)
                    .disabled(disabledValues.contains(values[i])).opacity(disabledValues.contains(values[i]) ? 0.4:1)
                    .help(L(titles[i])).accessibilityValue(L(selection==values[i] ? "已选中":"未选中"))
            }
        }.padding(3).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
    }
}

// Native text entry keeps the system selection and keyboard focus appearance.
enum NeutralInputAppearance {static func install() {}}
