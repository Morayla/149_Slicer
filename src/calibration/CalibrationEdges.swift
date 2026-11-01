import SceneKit
import simd

// Weld coincident CAD vertices before selecting boundaries and creases above 12°.
enum CalibrationEdges {
    private struct Vertex: Hashable {
        let x: Int, y: Int, z: Int
        init(_ p: SIMD3<Float>) {
            x = Int((p.x * 10_000).rounded())
            y = Int((p.y * 10_000).rounded())
            z = Int((p.z * 10_000).rounded())
        }
    }
    private struct Edge: Hashable { let a: Int, b: Int }
    private struct Face { let a: SIMD3<Float>, b: SIMD3<Float>, normal: SIMD3<Float> }

    static func geometry(_ mesh: SCNGeometry) -> SCNGeometry {
        let source = mesh.sources(for: .vertex)[0]
        let points: [SIMD3<Float>] = source.data.withUnsafeBytes { raw in
            (0..<source.vectorCount).map { i in
                let offset = source.dataOffset + i * source.dataStride
                return SIMD3(
                    raw.loadUnaligned(fromByteOffset: offset, as: Float.self),
                    raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                    raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
            }
        }
        var weld: [Vertex: Int] = [:]
        let ids = points.map { point -> Int in
            let key = Vertex(point)
            if let id = weld[key] { return id }
            let id = weld.count
            weld[key] = id
            return id
        }
        var edges: [Edge: Face] = [:]
        var lines: [SCNVector3] = []
        let threshold = cos(Float.pi / 15)
        for element in mesh.elements where element.primitiveType == .triangles {
            element.data.withUnsafeBytes { raw in
                func index(_ i: Int) -> Int {
                    let offset = i * element.bytesPerIndex
                    return element.bytesPerIndex == 2
                        ? Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                        : Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                }
                for i in stride(from: 0, to: element.primitiveCount * 3, by: 3) {
                    let triangle = [index(i), index(i + 1), index(i + 2)]
                    let cross = simd_cross(
                        points[triangle[1]] - points[triangle[0]], points[triangle[2]] - points[triangle[0]])
                    if simd_length_squared(cross) < 1e-12 { continue }
                    let normal = simd_normalize(cross)
                    for j in 0..<3 {
                        let a = triangle[j]
                        let b = triangle[(j + 1) % 3]
                        let key = Edge(a: min(ids[a], ids[b]), b: max(ids[a], ids[b]))
                        if let other = edges.removeValue(forKey: key) {
                            if simd_dot(normal, other.normal) <= threshold {
                                lines += [SCNVector3(points[a]), SCNVector3(points[b])]
                            }
                        } else {
                            edges[key] = Face(a: points[a], b: points[b], normal: normal)
                        }
                    }
                }
            }
        }
        for edge in edges.values { lines += [SCNVector3(edge.a), SCNVector3(edge.b)] }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: lines)],
            elements: [SCNGeometryElement(indices: (0..<Int32(lines.count)).map { $0 }, primitiveType: .line)])
    }
}
