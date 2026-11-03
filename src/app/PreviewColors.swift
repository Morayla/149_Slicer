import SwiftUI

// Shared multi-hue, ordered scale for quantitative analysis; never used for glass.
func previewMetricRGB(_ fraction: Double) -> [Double] {
    let stops: [[Double]] = [
        [0.36, 0.38, 0.93], [0.20, 0.68, 0.94], [0.24, 0.79, 0.62], [0.98, 0.78, 0.28], [1.0, 0.38, 0.34],
    ]
    let scaled = min(1, max(0, fraction)) * Double(stops.count - 1)
    let i = min(stops.count - 2, Int(scaled))
    let t = scaled - Double(i)
    return zip(stops[i], stops[i + 1]).map { $0 + ($1 - $0) * t }
}
let previewRoleRGB: [[Double]] = [
    [0.64, 0.67, 0.72], [0.30, 0.76, 0.71], [0.32, 0.60, 1.0], [0.82, 0.50, 0.94], [0.55, 0.58, 0.64],
]
let previewRoleColors: [Color] = previewRoleRGB.map { Color(red: $0[0], green: $0[1], blue: $0[2]) }
