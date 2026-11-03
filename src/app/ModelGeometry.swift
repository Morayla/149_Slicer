import SceneKit
import simd

struct ModelGeometry {
    let id = UUID()
    let geometry: SCNGeometry
    let dimensions: [Double]
    let center: SIMD3<Double>
    let placementPivot: SIMD2<Double>
    let interactive: Bool
    let parameters: SliceParameters
    let sourceMode: String

    init(_ prepared: NativePreparedModel, interactive: Bool = false) throws {
        self.interactive = interactive
        let profile = BeadProfile.samples
        parameters = prepared.shape.parameters
        sourceMode = parameters.text("SourceMode")
        let model = prepared.shape
        let (records, _, heights) = try SliceGcode.records(model.gcode, includeHeights: true)
        let computation = SliceComputation.current
        struct Deposit {
            let a, b, normal: SlicePoint
            let width, height: Double
        }
        func deposit(_ index: Int) -> Deposit? {
            guard records.indices.contains(index) else { return nil }
            let record = records[index]
            let h = heights[index] ?? model.parameters["H0"]
            guard let e = record.extrusion, e > 0, record.distance > 1e-9, h > 0,
                let a = record.before.point, let b = record.after.point
            else { return nil }
            let xy = hypot(b.x - a.x, b.y - a.y)
            let area = e / record.distance
            let width = area >= Double.pi * h * h / 4 ? area / h + h * SliceGeometry.edge : 4 * area / (Double.pi * h)
            guard xy > 1e-9, width.isFinite, width > 0 else { return nil }
            return Deposit(
                a: a, b: b, normal: SlicePoint(-(b.y - a.y) / xy, (b.x - a.x) / xy, 0), width: width, height: h)
        }
        func join(_ a: Deposit?, _ b: Deposit?) -> (side: SlicePoint, normal: SlicePoint, height: Double)? {
            guard let a, let b, simd_distance_squared(a.b, b.a) < 1e-12,
                abs(a.height - b.height) < 0.05 * max(a.height, b.height)
            else { return nil }
            let sum = a.normal + b.normal
            guard simd_length_squared(sum) > 1e-8 else { return nil }
            let normal = simd_normalize(sum)
            let cosine = simd_dot(normal, b.normal)
            guard cosine >= 0.5 else { return nil }
            let half = (a.width + b.width) / 4
            return (normal * (half / cosine), normal, (a.height + b.height) / 2)
        }
        var vertices = [SCNVector3]()
        var normals = [SCNVector3]()
        var coordinates = [CGPoint]()
        var indices = [Int32]()
        var low = SlicePoint(repeating: .infinity)
        var high = SlicePoint(repeating: -.infinity)
        vertices.reserveCapacity(records.count * 8)
        normals.reserveCapacity(records.count * 8)
        indices.reserveCapacity(records.count * 24)
        func vertex(_ point: SlicePoint, normal: SlicePoint, uv: CGPoint = .zero) {
            coordinates.append(uv)
            low = simd_min(low, point)
            high = simd_max(high, point)
            vertices.append(SCNVector3(Float(point.x), Float(point.z), Float(-point.y)))
            normals.append(SCNVector3(Float(normal.x), Float(normal.z), Float(-normal.y)))
        }
        func ring(_ point: SlicePoint, side: SlicePoint, normal: SlicePoint, height: Double) -> Int32 {
            let offset = Int32(vertices.count)
            let width = simd_length(side) * 2
            for sample in profile {
                let p = BeadProfile.point(sample, width: width, height: height)
                vertex(
                    point + side * (p.x * 2 / width) + SlicePoint(0, 0, p.z),
                    normal: normal * p.nx + SlicePoint(0, 0, p.nz))
            }
            return offset
        }
        func cap(_ point: SlicePoint, _ normal: SlicePoint, _ width: Double, _ height: Double, _ start: Bool) {
            let direction = SlicePoint(normal.y, -normal.x, 0) * (start ? -1 : 1)
            let center = Int32(vertices.count)
            vertex(point + SlicePoint(0, 0, -height / 2), normal: direction)
            for sample in profile {
                let p = BeadProfile.point(sample, width: width, height: height)
                vertex(point + normal * p.x + SlicePoint(0, 0, p.z), normal: direction)
            }
            for i in 0..<profile.count {
                let a = center + 1 + Int32(i)
                let b = center + 1 + Int32((i + 1) % profile.count)
                indices += start ? [center, a, b] : [center, b, a]
            }
        }
        var previous: Deposit?
        var current = deposit(0)
        var previousEnd: Int32?
        for index in records.indices {
            if index & 1023 == 0 { try computation?.check() }
            let next = deposit(index + 1)
            defer {
                previous = current
                current = next
            }
            guard let segment = current else {
                previousEnd = nil
                continue
            }
            let start = join(previous, segment)
            let end = join(segment, next)
            let a: Int32
            if start != nil, let previousEnd {
                a = previousEnd
            } else {
                a = ring(
                    segment.a, side: segment.normal * segment.width / 2, normal: segment.normal, height: segment.height)
            }
            let b = ring(
                segment.b, side: end?.side ?? segment.normal * segment.width / 2,
                normal: end?.normal ?? segment.normal, height: end?.height ?? segment.height)
            for face in 0..<profile.count {
                let i = Int32(face)
                let j = Int32((face + 1) % profile.count)
                indices += [a + i, b + i, a + j, a + j, b + i, b + j]
            }
            if start == nil { cap(segment.a, segment.normal, segment.width, segment.height, true) }
            if end == nil { cap(segment.b, segment.normal, segment.width, segment.height, false) }
            previousEnd = end == nil ? nil : b
        }
        guard !vertices.isEmpty else { throw SliceFailure("没有可显示的模型轮廓，请检查造型参数。") }
        center = (low + high) / 2
        var pathLow = SIMD2<Double>(repeating: .infinity)
        var pathHigh = SIMD2<Double>(repeating: -.infinity)
        for record in records where record.deposits {
            if let p = record.after.point {
                pathLow = simd_min(pathLow, SIMD2(p.x, p.y))
                pathHigh = simd_max(pathHigh, SIMD2(p.x, p.y))
            }
        }
        placementPivot = try SIMD2(
            SliceGcode.metadata(model.gcode, "PLACEMENT_CENTER_X", (pathLow.x + pathHigh.x) / 2),
            SliceGcode.metadata(model.gcode, "PLACEMENT_CENTER_Y", (pathLow.y + pathHigh.y) / 2))
        for i in vertices.indices {
            vertices[i].x -= CGFloat(center.x)
            vertices[i].y -= CGFloat(center.z)
            vertices[i].z += CGFloat(center.y)
        }
        dimensions = (0..<3).map { high[$0] - low[$0] }
        try computation?.check()
        geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: coordinates),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [BeadSurface.material(geometricProfile: true)]
    }
}
