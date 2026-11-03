import SceneKit
import SwiftUI

struct ModelPreview: NSViewRepresentable {
    let model: ModelGeometry
    let viewAction: Int
    @Binding var zoom: Double
    let panMode: Bool
    let source: String
    var shading = "rendered"
    var appearance = MaterialAppearance()
    var backgroundWhite = false
    var sharedCamera: PreviewCameraState?
    var outlineStrength = 0.0
    var xray = false
    var fields: [String: String] = [:]
    var active = true
    var xrayStrength = 0.5
    var placement: Workbench?
    var showBed = false
    var bedSize = [1000.0, 1000.0, 1000.0]
    final class Coordinator {
        let platform = PrintingPlatform()
        let gizmo = PlacementGizmo()
        var placementTool: PlacementTool?
        var id: UUID?
        var action = -1
        var object: SCNNode?
        var source = ""
        let material = MaterialRenderer.make()
        let background = ViewportBackgroundTransition()
        lazy var transparency = ModelTransparency.make()
        var transparent = false
        var appearance: MaterialAppearance?
        var shading = ""
        var xray = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> ZoomSceneView {
        let view = ZoomSceneView(
            frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = SCNScene()
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        PreviewQuality.apply(to: view)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        StudioLighting.install(in: view.scene!)
        view.scene!.lightingEnvironment.contents = GlassEnvironment.image
        view.scene!.lightingEnvironment.intensity = 0.55
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 10000
        camera.camera?.projectionDirection = .vertical
        view.scene!.rootNode.addChildNode(camera)
        view.pointOfView = camera
        return view
    }
    func updateNSView(_ view: ZoomSceneView, context: Context) {
        if !active && context.coordinator.id == model.id {
            context.coordinator.background.settle(white: backgroundWhite)
            view.cameraState = nil
            view.stopInteraction()
            return
        }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        PreviewQuality.apply(to: view)
        view.cameraState = nil
        let coordinator = context.coordinator
        let newModel = coordinator.id != model.id
        let transparent = !xray && shading != "solid" && appearance.transmission > 0 && appearance.metallic < 1
        if transparent != coordinator.transparent {
            view.technique = transparent ? coordinator.transparency : nil
            coordinator.transparent = transparent
        }
        coordinator.background.setWhite(backgroundWhite) { [weak view, weak coordinator] amount in
            guard let view, let coordinator else { return }
            let gray = ViewportBackgroundTransition.mix(0.063, 0.94, amount)
            view.scene?.background.contents = view.technique == nil ? NSColor(white: gray, alpha: 1) : nil
            if let technique = view.technique { ModelTransparency.setBackgroundLevel(gray, on: technique) }
            coordinator.material.setValue(NSNumber(value: ViewportBackgroundTransition.mix(0.90, 0.035, amount)), forKey: "xrayInk")
            coordinator.platform.setTone(amount)
            view.requestFrame()
        }
        if let technique = view.technique {
            view.scene?.background.contents = nil
            ModelTransparency.setBackgroundLevel(ViewportBackgroundTransition.mix(0.063, 0.94, coordinator.background.amount), on: technique)
        } else {
            view.scene?.background.contents = NSColor(white: ViewportBackgroundTransition.mix(0.063, 0.94, coordinator.background.amount), alpha: 1)
        }
        if coordinator.appearance != appearance || coordinator.shading != shading || coordinator.xray != xray {
            MaterialRenderer.apply(
                appearance, to: coordinator.material, solid: shading == "solid", accumulatesTransparency: transparent)
            coordinator.appearance = appearance
            coordinator.shading = shading
            coordinator.xray = xray
            coordinator.material.shaderModifiers?[.fragment] = xray ? ViewportSurfaceShader.xray : MaterialRenderer.transmissionShader
            coordinator.material.readsFromDepthBuffer = !xray
            if xray {
                coordinator.material.blendMode = .alpha
                coordinator.material.writesToDepthBuffer = false
                coordinator.material.isDoubleSided = false
            }
        }
        coordinator.material.setValue(NSNumber(value: outlineStrength), forKey: "outlineStrength")
        coordinator.material.setValue(NSNumber(value: xrayStrength), forKey: "xrayStrength")
        view.panMode = panMode
        view.placementTool = placement?.placementTool
        view.placementDragged = { [weak placement] a, b in placement?.dragPlacement(from: a, to: b) }
        view.placementRotated = { [weak placement] degrees in placement?.placementRotation += degrees }

        view.zoomChanged = { zoom = $0 }
        view.synchronizeZoom(sharedCamera?.valid == true && sharedCamera?.action == viewAction ? sharedCamera!.magnification : zoom)
        if newModel {
            coordinator.object?.removeFromParentNode()
            let geometry = model.geometry.copy() as! SCNGeometry
            geometry.materials = [coordinator.material]
            let object = SCNNode(geometry: geometry)
            view.scene!.rootNode.addChildNode(object)
            coordinator.object = object
            coordinator.id = model.id
        }
        coordinator.object?.simdScale = SIMD3(repeating: 1)
        let geometrySource = model.sourceMode
        let d = model.dimensions
        let center = placement?.placementCenter ?? SIMD2(Double(fields["CX"] ?? "500") ?? 500, Double(fields["CY"] ?? "500") ?? 500)
        let floor = model.center.z
        let worldPivot = SCNVector3(center.x - bedSize[0] / 2, floor, -(center.y - bedSize[1] / 2))
        coordinator.object?.pivot = SCNMatrix4MakeTranslation(CGFloat(model.placementPivot.x - model.center.x), 0,
            CGFloat(-(model.placementPivot.y - model.center.y)))
        coordinator.object?.position = worldPivot
        coordinator.object?.eulerAngles.y = CGFloat((placement?.placementRotation ?? 0) * .pi / 180)
        let fitCenter = coordinator.object?.convertPosition(SCNVector3Zero, to: nil) ?? worldPivot
        view.fitExtent = SIMD3(Float(d[0]), Float(d[2]), Float(d[1]))
        let toolChanged = coordinator.placementTool != placement?.placementTool
        if toolChanged {
            SCNTransaction.begin(); SCNTransaction.disableActions = false; SCNTransaction.animationDuration = 0.24
            coordinator.placementTool = placement?.placementTool
        }
        if coordinator.source != geometrySource || coordinator.action != viewAction {
            let command = coordinator.source != geometrySource ? 0 : viewAction % 10
            if command == 6 {
                view.frameTarget(SCNVector3Zero, extent: SIMD3(Float(bedSize[0]), 1, Float(bedSize[1])), orientation: 1)
            } else {
                view.frameTarget(fitCenter, extent: view.fitExtent, orientation: command == 2 ? nil : command)
            }
            coordinator.source = geometrySource
            coordinator.action = viewAction
        }
        view.applyScale()
        if active { view.connectCamera(sharedCamera, action: viewAction) }
        else { view.stopInteraction() }
        if toolChanged { SCNTransaction.commit() }
        coordinator.platform.update(size: bedSize, origin: SIMD3(bedSize[0] / 2, bedSize[1] / 2, 0), visible: showBed,
            tone: coordinator.background.amount, scene: view.scene!)
        coordinator.gizmo.update(placement?.placementTool,
            center: placement?.placementTool == .rotate ? worldPivot : SCNVector3(worldPivot.x, CGFloat(d[2]) + 2, worldPivot.z),
            span: max(d[0], d[1]), scene: view.scene!)
        view.requestFrame()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ZoomSceneView, context: Context) -> CGSize? {
        CGSize(width: max(1, proposal.width ?? 520), height: max(1, proposal.height ?? 360))
    }
    static func dismantleNSView(_ view: ZoomSceneView, coordinator: Coordinator) {
        view.stopInteraction()
        view.scene = nil
    }
}
