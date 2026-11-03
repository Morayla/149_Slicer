import SwiftUI

struct NozzleIcon: View {
    var body: some View {
        GeometryReader { proxy in
            Path { p in
                let w = proxy.size.width, h = proxy.size.height
                p.addRoundedRect(in: CGRect(x: w * 0.30, y: h * 0.08, width: w * 0.40, height: h * 0.22), cornerSize: CGSize(width: 1, height: 1))
                p.move(to: CGPoint(x: w * 0.20, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.53))
                p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.53))
                p.closeSubpath()
                p.move(to: CGPoint(x: w * 0.20, y: h * 0.53))
                p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.53))
                p.move(to: CGPoint(x: w * 0.50, y: h * 0.85))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.97))
            }.stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }.frame(width: 18, height: 18)
    }
}
