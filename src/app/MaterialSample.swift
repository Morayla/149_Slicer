import SceneKit
import SwiftUI

struct MaterialSample: NSViewRepresentable {
    let appearance: MaterialAppearance
    final class Coordinator {
        let material = MaterialRenderer.make(geometricProfile: false)
        let transparency = ModelTransparency.make()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = SCNScene()
        view.backgroundColor = .clear
        view.rendersContinuously = false
        PreviewQuality.apply(to: view)
        StudioLighting.install(in: view.scene!)
        view.scene!.lightingEnvironment.contents = GlassEnvironment.image
        view.scene!.lightingEnvironment.intensity = 0.55
        let cylinder = SCNCylinder(radius: 25, height: 48)
        cylinder.radialSegmentCount = 96
        cylinder.materials = [context.coordinator.material]
        view.scene!.rootNode.addChildNode(SCNNode(geometry: cylinder))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 38
        camera.position = SCNVector3(80, 55, 110)
        camera.look(at: SCNVector3Zero)
        view.scene!.rootNode.addChildNode(camera)
        view.pointOfView = camera
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        let transparent = appearance.transmission > 0 && appearance.metallic < 1
        MaterialRenderer.apply(appearance, to: context.coordinator.material, solid: false, accumulatesTransparency: transparent)
        view.technique = transparent ? context.coordinator.transparency : nil
        view.scene?.background.contents = transparent ? nil : NSColor(white: 0.12, alpha: 1)
        if transparent { ModelTransparency.setBackgroundLevel(0.12, on: context.coordinator.transparency) }
        view.needsDisplay = true
    }
}
