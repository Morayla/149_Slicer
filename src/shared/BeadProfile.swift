import Foundation

// A stadium section uses six segments per semicircle and interpolated normals.
// Widths narrower than the layer height use an ellipse.
enum BeadProfile {
    static let samples: [(side: Double, x: Double, z: Double)] = [1.0, -1.0].flatMap { side in
        (0...6).map { i in
            let angle = (side > 0 ? Double.pi / 2 : -Double.pi / 2) - Double(i) * Double.pi / 6
            return (side, cos(angle), sin(angle))
        }
    }
    static let count = samples.count
    static func point(_ sample: (side: Double, x: Double, z: Double), width: Double, height: Double) -> (x: Double, z: Double, nx: Double, nz: Double) {
        let rx = min(width, height) / 2, rz = height / 2
        let nx = sample.x / rx, nz = sample.z / rz, length = hypot(nx, nz)
        return (sample.side * max(0, width - height) / 2 + sample.x * rx,
                sample.z * rz - rz, nx / length, nz / length)
    }
}
