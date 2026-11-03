import Foundation

final class EllipseSliceSections: SliceSections {
    let height: Double
    let radius: Double
    private let points: [SlicePoint]
    init(_ p: SliceParameters) throws {
        let a = p["EllipseMajor"] / 2
        let b = p["EllipseMinor"] / 2
        height = p["CH"]
        radius = max(a, b)
        var count = max(128, Int(ceil(Double.pi * sqrt(radius / (2 * p["Tolerance"])))))
        count = 4 * Int(ceil(Double(count) / 4))
        guard count <= 2000 else { throw SliceFailure("椭圆尺寸或精度过高，请减小尺寸或降低精度。") }
        let angle = SliceGeometry.modulo(p["EllipseRotation"], 360) * Double.pi / 180
        let c = cos(angle)
        let s = sin(angle)
        points = (0..<count).map { i in
            let t = SliceGeometry.tau * Double(i) / Double(count)
            let x = a * cos(t)
            let y = b * sin(t)
            return SlicePoint(x * c - y * s, x * s + y * c, 0)
        }
    }
    func loop(_ z: Double) throws -> [SlicePoint] { points }
}
