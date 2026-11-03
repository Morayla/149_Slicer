import Combine
import SwiftUI

// Ranges preserve G-code order, including constant-Z and non-planar paths.
final class PathTimeline: ObservableObject {
    @Published var layer = 1
    @Published var progress = 1.0
    @Published var playing = false
    private(set) var data: PreviewResult?
    private(set) var layers: [PreviewResult.Layer] = []
    private var cumulative: [[Double]] = []
    func load(_ preview: PreviewResult) {
        playing = false
        data = preview
        layers = preview.layers ?? [PreviewResult.Layer(start: 0, end: preview.segments.count, z: preview.height)]
        layers = layers.filter { $0.start >= 0 && $0.end <= (preview.segments.count) && $0.end > $0.start }
        cumulative = layers.map { group in
            var sums = [0.0]
            for i in group.start..<group.end {
                let s = preview.segments[i]
                sums.append(sums.last! + sqrt(pow(s[3] - s[0], 2) + pow(s[4] - s[1], 2) + pow(s[5] - s[2], 2)))
            }
            return sums
        }
        layer = max(1, layers.count)
        progress = 1
    }
    var cursor: (end: Int, fraction: Double, point: [Double]?) {
        guard let data = data, !layers.isEmpty else { return (0, 1, nil) }
        let li = min(layers.count - 1, max(0, layer - 1))
        let g = layers[li]
        let c = cumulative[li]
        let target = min(1, max(0, progress)) * (c.last ?? 0)
        var lo = 0
        var hi = c.count - 1
        while lo + 1 < hi {
            let m = (lo + hi) / 2
            if c[m] <= target { lo = m } else { hi = m }
        }
        let index = min(g.end - 1, g.start + lo)
        let s = data.segments[index]
        let f = progress >= 1 ? 1 : min(1, max(0, (target - c[lo]) / max(1e-12, c[lo + 1] - c[lo])))
        var point = [Double]()
        for j in 0..<3 { point.append(s[j] + (s[j + 3] - s[j]) * f) }
        return (index + 1, f, point)
    }
    func tick(elapsed: Double) {
        guard playing, !layers.isEmpty else { return }
        if progress >= 1 {
            if layer >= layers.count {
                playing = false
                return
            }
            layer += 1
            progress = 0
        } else {
            progress = min(1, progress + elapsed * 0.1)
        }
    }
    func togglePlayback() {
        if !playing && layer == layers.count && progress >= 1 {
            layer = 1
            progress = 0
        }
        playing.toggle()
    }
}
struct LayerOverlay: View {
    @ObservedObject var timeline: PathTimeline
    var body: some View {
        VStack(spacing: 8) {
            Text("\(timeline.layer)").monospacedDigit().font(.caption)
            GeometryReader { proxy in
                GlassSlider(value: Binding(get: { Double(timeline.layer) }, set: {
                    timeline.playing = false; timeline.layer = Int($0.rounded())
                }), range: 1...Double(max(2, timeline.layers.count)), step: 1, label: "观察层")
                .frame(width: proxy.size.height, height: 24)
                .rotationEffect(.degrees(-90))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            Text("\(timeline.layers.count)").font(.caption2).foregroundStyle(.secondary)
        }.padding(8).frame(width: 38).frame(maxHeight: 260)
            .background(.regularMaterial, in: Capsule()).disabled(timeline.layers.count < 2)
    }
}
struct PlaybackOverlay: View {
    @ObservedObject var timeline: PathTimeline
    let enabled: Bool
    let mass: Double, minutes: Double
    var body: some View {
        HStack(spacing: 10) {
            ViewportIconButton(title: timeline.playing ? "暂停" : "演示", symbol: timeline.playing ? "pause.fill" : "play.fill") {
                timeline.togglePlayback()
            }
            GlassSlider(value: Binding(get: { timeline.progress }, set: { timeline.playing = false; timeline.progress = $0 }),
                        range: 0...1, label: "层内路径进度").frame(height: 24)
            Text(String(format: "%.1f g · %.0f min", mass, ceil(minutes))).font(.caption).monospacedDigit().fixedSize()
        }.padding(6).frame(maxWidth: 560).background(.regularMaterial, in: Capsule()).disabled(!enabled)
            .task(id: enabled && timeline.playing) {
                guard enabled && timeline.playing else { return }
                let clock = ContinuousClock()
                var deadline = clock.now
                var previous = ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled && timeline.playing {
                    deadline += .nanoseconds(16_666_667)
                    do { try await clock.sleep(until: deadline, tolerance: .microseconds(250)) } catch { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    timeline.tick(elapsed: now - previous)
                    previous = now
                    if deadline < clock.now - .milliseconds(100) { deadline = clock.now }
                }
            }.onChange(of: enabled) { if !$0 { timeline.playing = false } }
            .onDisappear { timeline.playing = false }
    }
}
