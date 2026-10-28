import SwiftUI
import AppKit

struct ContextHelp:View {
    @ObservedObject private var language=AppLanguage.shared
    let texts:[String]
    @State private var expanded=false
    init(_ texts:String...) {self.texts=texts}
    var body:some View {
        DisclosureGroup(isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:8) {
                ForEach(texts.indices,id:\.self) {index in uiText(texts[index])}
            }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        } label:{Label(L("参数说明"),systemImage:"info.circle").font(.caption).foregroundStyle(.secondary)}
    }
}

// A template image also works in native toolbar and menu labels.
enum FabricationSymbol {
    static let image:NSImage = {
        let image=NSImage(size:NSSize(width:18,height:18),flipped:true) {rect in
            let p=NSBezierPath()
            func pt(_ x:CGFloat,_ y:CGFloat)->NSPoint {NSPoint(x:x*18,y:y*18)}
            p.move(to:pt(0.16,0.86));p.line(to:pt(0.16,0.14));p.line(to:pt(0.84,0.14));p.line(to:pt(0.84,0.86))
            p.move(to:pt(0.08,0.86));p.line(to:pt(0.92,0.86))
            p.move(to:pt(0.16,0.35));p.line(to:pt(0.84,0.35))
            p.appendRect(NSRect(x:7.2,y:5.4,width:3.6,height:3.6))
            p.move(to:pt(0.44,0.50));p.line(to:pt(0.5,0.61));p.line(to:pt(0.56,0.50))
            p.move(to:pt(0.35,0.75));p.line(to:pt(0.65,0.75))
            p.lineWidth=1.25;p.lineCapStyle = .round;p.lineJoinStyle = .round
            NSColor.black.setStroke();p.stroke();return true
        }
        image.isTemplate=true;return image
    }()
}
struct FabricationIcon:View {var body:some View {Image(nsImage:FabricationSymbol.image).accessibilityHidden(true)}}

// Hopper with loose pellets versus an enclosed filament spool.
// Both are template vectors, so toolbar tint follows the system appearance.
enum DryerSymbol {
    static let pellet=make(spool:false)
    static let ams=make(spool:true)
    private static func make(spool:Bool)->NSImage {
        let image=NSImage(size:NSSize(width:18,height:18),flipped:true) {_ in
            let p=NSBezierPath();p.lineWidth=1.25;p.lineCapStyle = .round;p.lineJoinStyle = .round
            if spool {
                p.appendRoundedRect(NSRect(x:1.5,y:2.5,width:15,height:13),xRadius:2,yRadius:2)
                p.appendOval(in:NSRect(x:4,y:5,width:8,height:8))
                p.appendOval(in:NSRect(x:7,y:8,width:2,height:2))
                p.move(to:NSPoint(x:14,y:6));p.line(to:NSPoint(x:14,y:9))
                p.move(to:NSPoint(x:14,y:12));p.line(to:NSPoint(x:14,y:12.2))
            } else {
                p.move(to:NSPoint(x:3,y:2));p.line(to:NSPoint(x:15,y:2))
                p.move(to:NSPoint(x:4,y:2));p.line(to:NSPoint(x:4,y:10));p.line(to:NSPoint(x:8,y:14))
                p.line(to:NSPoint(x:8,y:16));p.line(to:NSPoint(x:10,y:16));p.line(to:NSPoint(x:10,y:14))
                p.line(to:NSPoint(x:14,y:10));p.line(to:NSPoint(x:14,y:2))
                for (x,y) in [(6.5,5.0),(10.5,5.0),(8.5,8.5)] {p.appendOval(in:NSRect(x:x,y:y,width:1.5,height:1.5))}
            }
            NSColor.black.setStroke();p.stroke();return true
        }
        image.isTemplate=true;return image
    }
}
