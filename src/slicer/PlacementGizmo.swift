import SceneKit

final class PlacementGizmo {
    private let root = SCNNode()
    private var tool: PlacementTool?
    init() { root.name = "placement-handles"; root.categoryBitMask = 4 }
    func update(_ tool: PlacementTool?, center: SCNVector3, span: Double, scene: SCNScene) {
        if root.parent == nil { scene.rootNode.addChildNode(root) }
        root.isHidden = tool == nil
        root.position = center
        root.scale = SCNVector3(span, span, span)
        guard tool != self.tool else { return }
        self.tool = tool
        root.childNodes.forEach { $0.removeFromParentNode() }
        func add(_ geometry: SCNGeometry, _ color: NSColor, position: SCNVector3 = SCNVector3Zero) -> SCNNode {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.readsFromDepthBuffer = false
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.categoryBitMask = 4
            node.position = position
            node.renderingOrder = 100
            root.addChildNode(node)
            return node
        }
        switch tool {
        case .move:
            for (color, angle) in [(NSColor.systemRed, Float.pi / 2), (NSColor.systemGreen, Float(0))] {
                let axis = add(SCNCylinder(radius: 0.006, height: 0.30), color)
                axis.eulerAngles = angle == 0 ? SCNVector3(-Float.pi / 2, 0, 0) : SCNVector3(0, 0, -Float.pi / 2)
                axis.position = angle == 0 ? SCNVector3(0, 0, -0.15) : SCNVector3(0.15, 0, 0)
                let tip = add(SCNCone(topRadius: 0, bottomRadius: 0.023, height: 0.07), color)
                tip.eulerAngles = axis.eulerAngles
                tip.position = angle == 0 ? SCNVector3(0, 0, -0.32) : SCNVector3(0.32, 0, 0)
            }
        case .rotate:
            _ = add(SCNTorus(ringRadius: 0.60, pipeRadius: 0.006), .controlAccentColor)
        case nil: break
        }
    }
}
