import SceneKit

final class PrintingPlatform {
    private let node = SCNNode()
    private let material = SCNMaterial()
    private var size: [Double] = []
    private var tone = Double.nan
    init() {
        node.name = "printing-platform"
        node.categoryBitMask = 2
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        material.blendMode = .alpha
    }
    func update(size: [Double], origin: SIMD3<Double>, visible: Bool, tone: Double, scene: SCNScene) {
        if node.parent == nil { scene.rootNode.addChildNode(node) }
        node.isHidden = !visible
        node.position = SCNVector3(-origin.x, -origin.z, origin.y)
        setTone(tone)
        guard size != self.size else { return }
        self.size = size
        var points: [SCNVector3] = []
        var colors: [Float] = []
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, border: Bool) {
            points += [SCNVector3(x1, -0.4, -y1), SCNVector3(x2, -0.4, -y2)]
            let alpha: Float = border ? 0.65 : 0.25
            colors += [1, 1, 1, alpha, 1, 1, 1, alpha]
        }
        let w = size[0], h = size[1], step = max(w, h) > 400 ? 50.0 : 20.0
        for x in stride(from: 0.0, through: w, by: step) { line(x, 0, x, h, border: x == 0 || x == w) }
        for y in stride(from: 0.0, through: h, by: step) { line(0, y, w, y, border: y == 0 || y == h) }
        if w.truncatingRemainder(dividingBy: step) != 0 { line(w, 0, w, h, border: true) }
        if h.truncatingRemainder(dividingBy: step) != 0 { line(0, h, w, h, border: true) }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: points.count,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let indices = (0..<points.count).map { Int32($0) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: points), colorSource],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        geometry.materials = [material]
        node.geometry = geometry
    }
    func setTone(_ amount: Double) {
        guard tone != amount else { return }
        tone = amount
        material.multiply.contents = NSColor(white: ViewportBackgroundTransition.mix(0.95, 0.10, amount), alpha: 1)
    }
}
