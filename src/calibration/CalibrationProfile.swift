import SceneKit
import SwiftUI

// One native, demand-rendered view. Each captured band retains its own measured radius.
struct CalibrationProfile: NSViewRepresentable {
    @AppStorage("previewQuality") private var previewQuality = "detailed"
    let config: CalibrationConfig
    let rows: [CalibrationSample]
    let selected: Int?
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(
            frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.rendersContinuously = false
        view.isPlaying = false
        PreviewQuality.apply(to: view)
        view.setAccessibilityLabel(L("按测量层显示的三维样件轮廓"))
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        PreviewQuality.apply(to: view)
        if context.coordinator.update(config, rows: rows, selected: selected, dark: colorScheme == .dark) {
            view.needsDisplay = true
        }
    }
    final class Coordinator {
        let scene = SCNScene(), camera = SCNNode(), rings = SCNNode()
        var previous: CalibrationConfig?, signature = "", previousDark: Bool?
        init() {
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.zNear = 0.1
            camera.camera?.zFar = 2000
            camera.position = SCNVector3(210, 150, 340)
            camera.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(rings)
        }
        func update(_ c: CalibrationConfig, rows: [CalibrationSample], selected: Int?, dark: Bool) -> Bool {
            let key = rows.map { "\($0.layer):\($0.radialErrorMm)" }.joined(separator: ",") + ":\(selected ?? 0)"
            guard previous != c || key != signature || previousDark != dark else { return false }
            previous = c
            signature = key
            previousDark = dark
            rings.childNodes.forEach { $0.removeFromParentNode() }
            camera.camera?.orthographicScale = max(c.height * 0.62 + c.diameter * 0.18, c.diameter * 0.64)
            let captured = Dictionary(uniqueKeysWithValues: rows.map { ($0.layer, $0) })
            let count = min(600, Int(ceil(c.height / c.step)))
            func circle(_ radius: Double, _ y: Double, _ opacity: Double, _ accent: Bool = false) {
                var points = [SCNVector3]()
                var indices = [Int32]()
                for i in 0...128 {
                    let a = Double(i) * 2 * .pi / 128
                    points.append(SCNVector3(radius * cos(a), y - c.height / 2, radius * sin(a)))
                    if i < 128 { indices += [Int32(i), Int32(i + 1)] }
                }
                let geometry = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: points)],
                    elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = dark ? NSColor.white : NSColor.black
                material.transparency = opacity
                material.writesToDepthBuffer = false
                geometry.materials = [material]
                rings.addChildNode(SCNNode(geometry: geometry))
            }
            let ghost = SCNNode(geometry: CalibrationRenderer.specimenGeometry(c))
            ghost.position.y = CGFloat(-c.height / 2)
            ghost.geometry?.materials = [CalibrationMaterials.constant(dark ? .white : .black, opacity: 0.018)]
            rings.addChildNode(ghost)
            for row in rows {
                let band = SCNNode(
                    geometry: CalibrationRenderer.specimenGeometry(
                        c, firstLayer: row.layer, lastLayer: row.layer, errorAtHeight: { _ in row.radialErrorMm }))
                band.position.y = CGFloat(-c.height / 2)
                band.geometry?.materials = [CalibrationMaterials.xray(white: !dark, strength: 1, exponent: 2)]
                rings.addChildNode(band)
            }
            for layer in 1...count {
                let top = c.height - Double(layer - 1) * c.step
                let bottom = max(0, c.height - Double(layer) * c.step)
                let row = captured[layer]
                let error = row?.radialErrorMm ?? c.radialError(at: (top + bottom) / 2)
                let radius = c.diameter / 2 + error
                let opacity = row == nil ? 0.09 : 0.55
                circle(radius, (top + bottom) / 2, selected == layer ? 0.95 : opacity, selected == layer)
                if row != nil {
                    circle(radius - 0.28 * (top - bottom), top, 0.3)
                    circle(c.diameter / 2 - c.lineWidth + 0.28 * (top - bottom), top, 0.22)
                }
            }
            circle(c.diameter / 2 - c.lineWidth, c.height, 0.18)
            circle(c.diameter / 2, c.height, 0.22)
            circle(c.diameter / 2, 0, 0.15)
            return true
        }
    }
}
