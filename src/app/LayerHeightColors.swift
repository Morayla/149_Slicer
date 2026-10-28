import Foundation

/// Categorical print-layer colors. Local extrusion gaps must never enter this scale.
struct LayerHeightColors {
    struct Entry: Identifiable {
        let id: Double
        let rgb: [Double]
        var label: String {
            var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), id)
            while text.last == "0" { text.removeLast() }
            if text.last == "." { text.removeLast() }
            return text
        }
    }
    let entries: [Entry]
    private let indices: [Double: Int]
    static func key(_ height: Double) -> Double { (height * 1_000_000).rounded() / 1_000_000 }
    init(heights: [Double]) {
        let heights = Set(heights.filter { $0.isFinite && $0 > 0 }.map(Self.key)).sorted()
        // Exported Z coordinates are rounded. Subtracting them can make a
        // single planned pitch alternate by 0.00001 mm. Merge that noise
        // for BOTH the legend and mesh colors; leave toolpaths untouched.
        // Compare with the group's first value, preventing tolerance chains.
        var representatives: [Double] = []
        var lookup: [Double: Int] = [:]
        for height in heights {
            if let anchor = representatives.last, height-anchor <= 0.00005+1e-12 {
                lookup[height] = representatives.count-1
            } else {
                representatives.append(height)
                lookup[height] = representatives.count-1
            }
        }
        entries = representatives.enumerated().map { Entry(id: $0.element, rgb: Self.rgb($0.offset)) }
        indices = lookup
    }
    func index(_ height: Double) -> Int? {
        guard height.isFinite else { return nil }
        return indices[Self.key(height)]
    }
    func color(_ height: Double) -> [Double] {
        guard let i = index(height) else { return [0.48, 0.52, 0.57] }
        return entries[i].rgb
    }
    private static func rgb(_ index: Int) -> [Double] {
        let palette: [[Double]] = [
            [0.12,0.48,1.00], [0.95,0.20,0.22], [1.00,0.80,0.08],
            [0.16,0.76,0.36], [0.69,0.35,0.94], [1.00,0.46,0.10],
            [0.08,0.80,0.84], [0.98,0.37,0.69], [0.57,0.70,0.12],
            [0.58,0.44,0.29], [0.46,0.55,0.98], [0.65,0.75,0.80]
        ]
        if index < palette.count { return palette[index] }
        // Additional heights get distinct solid colors, never an interpolated ramp
        // and never a repeated palette entry assigned to a different height.
        let hue = (Double(index-palette.count) * 0.618033988749895 + 0.07).truncatingRemainder(dividingBy: 1) * 6
        let saturation = [0.72, 0.52, 0.87][(index-palette.count) % 3]
        let value = [0.96, 0.78][((index-palette.count) / 3) % 2]
        let c = value*saturation, x = c*(1-abs(hue.truncatingRemainder(dividingBy: 2)-1)), m = value-c
        let components: [Double]
        switch Int(hue) {
        case 0: components = [c,x,0]
        case 1: components = [x,c,0]
        case 2: components = [0,c,x]
        case 3: components = [0,x,c]
        case 4: components = [x,0,c]
        default: components = [c,0,x]
        }
        return components.map { $0+m }
    }
}
