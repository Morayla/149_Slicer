import AppKit
import SceneKit
import SwiftUI

final class ZoomSceneView: SCNView {
    var cameraState: PreviewCameraState?
    private(set) var loadedPreviewID: String?
    func didLoadPreview(_ id: String) { loadedPreviewID = id }
    var zoomChanged: ((Double) -> Void)?
    var panMode = false
    var placementTool: PlacementTool?
    var placementDragged: ((SIMD2<Double>, SIMD2<Double>) -> Void)?
    var placementRotated: ((Double) -> Void)?
    var placementDragChanged: ((Bool) -> Void)?
    private var draggingObject = false
    private func platformPoint(_ point: CGPoint) -> SIMD2<Double> {
        let a = unprojectPoint(SCNVector3(point.x, point.y, 0))
        let b = unprojectPoint(SCNVector3(point.x, point.y, 1))
        let t = abs(b.y - a.y) > 1e-8 ? -a.y / (b.y - a.y) : 0
        return SIMD2(Double(a.x + (b.x - a.x) * t), -Double(a.z + (b.z - a.z) * t))
    }
    var target = SIMD3<Float>(repeating: 0)
    var yaw: Float = 0.59, pitch: Float = 0.53, distance: Float = 1000
    private var pointer = NSPoint.zero
    var fitExtent = SIMD3<Float>(100, 100, 100)
    var magnification = 1.0
    var fittedScale = 100.0
    private var fittedSize = NSSize.zero
    private var idleRender: DispatchWorkItem?
    private var zoomNotification: DispatchWorkItem?
    private var interacting = false
    var playing = false {
        didSet { if oldValue != playing { updateRenderLoop() } }
    }
    private func updateRenderLoop() {
        rendersContinuously = interacting || playing
        if rendersContinuously { needsDisplay = false } else { requestFrame() }
    }
    func requestFrame() {
        if !rendersContinuously { needsDisplay = true }
    }
    func beginInteraction() {
        idleRender?.cancel()
        if !interacting {
            interacting = true
            updateRenderLoop()
        }
        let stop = DispatchWorkItem { [weak self] in
            self?.interacting = false
            self?.updateRenderLoop()
        }
        idleRender = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: stop)
    }
    func synchronizeZoom(_ value: Double) {
        if zoomNotification == nil { magnification = value }
    }
    func zoomBy(_ factor: Double) {
        beginInteraction()
        magnification = min(30, max(0.25, magnification * factor))
        // Move the camera in the input event, before SwiftUI recomputes panels.
        applyScale()
        guard zoomNotification == nil else { return }
        let notification = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.zoomNotification = nil
            self.zoomChanged?(self.magnification)
        }
        zoomNotification = notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60, execute: notification)
    }
    func stopInteraction() {
        idleRender?.cancel()
        zoomNotification?.cancel()
        zoomNotification = nil
        interacting = false
        playing = false
        rendersContinuously = false
    }
    override func layout() {
        super.layout()
        if bounds.size != fittedSize {
            fittedSize = bounds.size
            if cameraState?.valid != true { fitScale() } else { applyScale() }
        }
    }
    func fitScale() {
        guard let node = pointOfView else { return }
        let m = node.simdWorldTransform
        let right = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let up = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let width = Double(simd_dot(simd_abs(right), fitExtent))
        let height = Double(simd_dot(simd_abs(up), fitExtent))
        let aspect = max(0.1, Double(bounds.width / max(1, bounds.height)))
        fittedScale = max(height, width / aspect, 1) * 0.60
        applyScale()
    }
    func applyScale() {
        let scale = fittedScale / max(0.25, magnification)
        guard pointOfView?.camera?.orthographicScale != scale else { return }
        pointOfView?.camera?.orthographicScale = scale
        saveCamera()
        requestFrame()
    }
    func frameTarget(_ center: SCNVector3, extent: SIMD3<Float>, orientation: Int?) {
        target = SIMD3(Float(center.x), Float(center.y), Float(center.z))
        fitExtent = extent
        distance = max(extent.x, extent.y, extent.z) * 3 + 100
        if let orientation = orientation {
            switch orientation {
            case 1:
                yaw = 0
                pitch = Float.pi / 2
            case 3:
                yaw = 0
                pitch = 0
            case 4:
                yaw = -Float.pi / 2
                pitch = 0
            default:
                yaw = 0.59
                pitch = 0.53
            }
        }
        positionCamera()
        fitScale()
    }
    func positionCamera() {
        beginInteraction()
        guard let camera = pointOfView else { return }
        camera.simdPosition = target + distance * SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        let up: SCNVector3 = abs(cos(pitch)) < 0.001 ? SCNVector3(-sin(yaw), 0, -cos(yaw)) : SCNVector3(0, 1, 0)
        saveCamera()
        camera.look(at: SCNVector3(target.x, target.y, target.z), up: up, localFront: SCNVector3(0, 0, -1))
        requestFrame()
    }
    func pan(dx: Double, dy: Double) {
        guard let camera = pointOfView, let lens = camera.camera else { return }
        let m = camera.simdWorldTransform
        let k = Float(2 * lens.orthographicScale / max(1, bounds.height))
        let right = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let up = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        target -= right * Float(dx) * k + up * Float(dy) * k
        positionCamera()
    }
    override func mouseDown(with event: NSEvent) {
        beginInteraction()
        pointer = convert(event.locationInWindow, from: nil)
        let hit =
            placementTool == nil
            ? nil
            : (hitTest(pointer, options: [.categoryBitMask: 4, .firstFoundOnly: true]).first
                ?? hitTest(pointer, options: [.categoryBitMask: 1, .firstFoundOnly: true]).first)
        draggingObject = event.type == .leftMouseDown && placementTool != nil && hit != nil
        if draggingObject { placementDragChanged?(true) }
    }
    override func mouseUp(with event: NSEvent) {
        if draggingObject { placementDragChanged?(false) }
        draggingObject = false
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if draggingObject {
            beginInteraction()
            if placementTool == .rotate {
                let axis = SIMD3<Float>(0, 1, 0)
                if let a = rotationPoint(pointer, axis: axis), let b = rotationPoint(p, axis: axis) {
                    let angle = atan2(simd_dot(axis, simd_cross(a, b)), simd_dot(a, b))
                    placementRotated?(Double(angle) * 180 / .pi)
                }
            } else {
                placementDragged?(platformPoint(pointer), platformPoint(p))
            }
            pointer = p
            return
        }
        let dx = Double(p.x - pointer.x)
        let dy = Double(p.y - pointer.y)
        pointer = p
        if panMode || event.modifierFlags.contains(.shift) {
            pan(dx: dx, dy: dy)
        } else {
            yaw -= Float(dx) * 0.008
            pitch = min(1.5706, max(-1.50, pitch - Float(dy) * 0.008))
            positionCamera()
        }
    }
    private func rotationPoint(_ point: CGPoint, axis: SIMD3<Float>) -> SIMD3<Float>? {
        guard
            let center = scene?.rootNode.childNode(withName: "placement-handles", recursively: false)?.simdWorldPosition
        else { return nil }
        let near = unprojectPoint(SCNVector3(point.x, point.y, 0))
        let far = unprojectPoint(SCNVector3(point.x, point.y, 1))
        let start = SIMD3(Float(near.x), Float(near.y), Float(near.z))
        let ray = SIMD3(Float(far.x), Float(far.y), Float(far.z)) - start
        let divisor = simd_dot(ray, axis)
        guard abs(divisor) > 0.00001 else { return nil }
        let radial = start + ray * (simd_dot(center - start, axis) / divisor) - center
        return simd_length_squared(radial) > 0.00001 ? simd_normalize(radial) : nil
    }
    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func rightMouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pan(dx: p.x - pointer.x, dy: p.y - pointer.y)
        pointer = p
    }
    override func otherMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func otherMouseDragged(with event: NSEvent) { rightMouseDragged(with: event) }
    static func scrollZoomFactor(delta: Double, precise: Bool) -> Double {
        exp(min(0.25, max(-0.25, delta * (precise ? 0.012 : 0.08))))
    }
    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        // Magic Mouse also reports precise deltas; never infer pan from that flag.
        zoomBy(Self.scrollZoomFactor(delta: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas))
    }
    override func magnify(with event: NSEvent) { zoomBy(exp(min(0.3, max(-0.3, Double(event.magnification))))) }
}

// Build the path once; playback changes draw ranges and only clips the active bead.
struct BeadPreview: NSViewRepresentable {
    let data: PreviewResult
    let zLimit: Double
    let showTravel: Bool
    let showBed: Bool
    let mode: PreviewMode
    let viewAction: Int
    @Binding var zoom: Double
    var visibleCount: Int? = nil
    var segmentFraction: Double = 1
    var nozzlePoint: [Double]? = nil
    var asLines = false
    var panMode = false
    var onReady: (() -> Void)?
    var sharedCamera: PreviewCameraState?
    var outlineStrength = 0.0
    var backgroundWhite = false
    var xray = false
    var active = true
    var whiteModel = false
    var xrayStrength = 0.5
    var playing = false
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        _ = GlassEnvironment.image
        let view = ZoomSceneView(
            frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = SCNScene()
        view.backgroundColor = NSColor.clear
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        StudioLighting.install(in: view.scene!)
        PreviewQuality.apply(to: view)
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 10000
        camera.camera?.projectionDirection = .vertical
        view.scene!.rootNode.addChildNode(camera)
        view.pointOfView = camera
        context.coordinator.camera = camera
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SCNView, context: Context) -> CGSize? {
        let width = proposal.width ?? 520
        let height = proposal.height ?? 300
        return CGSize(width: width.isFinite ? max(1, width) : 520, height: height.isFinite ? max(1, height) : 300)
    }
    func updateNSView(_ view: SCNView, context: Context) {
        if !active, let viewport = view as? ZoomSceneView, viewport.loadedPreviewID == data.sha256 {
            context.coordinator.settleBackground(backgroundWhite)
            viewport.cameraState = nil
            viewport.stopInteraction()
            return
        }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        PreviewQuality.apply(to: view)
        context.coordinator.setBackground(backgroundWhite, view: view)
        (view as? ZoomSceneView)?.playing = active && playing
        (view as? ZoomSceneView)?.cameraState = nil
        context.coordinator.update(view, self)
        if active {
            (view as? ZoomSceneView)?.connectCamera(sharedCamera, action: viewAction)
        } else {
            (view as? ZoomSceneView)?.stopInteraction()
        }
    }
    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.pending?.cancel()
        coordinator.cancellation.cancel()
        coordinator.revision += 1
        (view as? ZoomSceneView)?.stopInteraction()
        view.scene = nil
    }
    final class Coordinator {
        private let background = ViewportBackgroundTransition()
        private let platform = PrintingPlatform()
        func settleBackground(_ white: Bool) { background.settle(white: white) }
        func setBackground(_ white: Bool, view: SCNView) {
            background.setWhite(white) { [weak self, weak view] amount in
                guard let self, let view else { return }
                view.scene?.background.contents = NSColor(
                    white: ViewportBackgroundTransition.mix(0.063, 0.94, amount), alpha: 1)
                view.scene?.rootNode.enumerateChildNodes { node, _ in self.applyTone(node) }
                self.platform.setTone(amount)
                (view as? ZoomSceneView)?.requestFrame()
            }
        }
        private func applyTone(_ node: SCNNode) {
            for material in node.geometry?.materials ?? [] {
                material.setValue(
                    NSNumber(value: ViewportBackgroundTransition.mix(0.933, 0.09, background.amount)), forKey: "xrayInk"
                )
                if node.name == "bed-lines" || node.name == "bed-label" {
                    material.diffuse.contents = NSColor(
                        white: ViewportBackgroundTransition.mix(1, 0.12, background.amount), alpha: 0.65)
                }
            }
        }
        private var whiteBackground = false
        private var outlineStrength = 0.0
        private var xray = false
        private var whiteModel = false
        private var xrayStrength = 0.5
        private func updateBackground(_ root: SCNNode) {
            root.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] {
                    material.setValue(NSNumber(value: outlineStrength), forKey: "outlineStrength")
                    if node.name == "material-body" {
                        material.isDoubleSided = false
                        material.setValue(NSNumber(value: whiteModel ? 0.0 : 1.0), forKey: "xrayColor")
                        material.setValue(NSNumber(value: xrayStrength), forKey: "xrayStrength")
                        material.shaderModifiers?[.surface] =
                            whiteModel ? "#pragma body\n_surface.diffuse.rgb = float3(0.8);" : nil
                        material.shaderModifiers?[.fragment] =
                            xray
                            ? ViewportSurfaceShader.xray : (outlineStrength > 0 ? ViewportSurfaceShader.outline : nil)
                        material.lightingModel = xray ? .constant : .lambert
                        material.blendMode = .alpha
                        material.readsFromDepthBuffer = !xray
                        material.writesToDepthBuffer = !xray
                    }
                }
                self.applyTone(node)
            }
        }
        var camera: SCNNode?
        var pending: DispatchWorkItem?
        var key = "", cameraKey = ""
        var action = -1
        var nozzle: SCNNode?
        var cachedFrames: (sha: String, bed: BeadMesh.Frame, model: BeadMesh.Frame)?
        var revision = 0
        var cancellation = MeshCancellation()
        struct DrawRange {
            let node: SCNNode
            let element: SCNGeometryElement
            let ends: [Int]
        }
        var ranges = [DrawRange]()
        var latest: BeadPreview?
        var partial: SCNNode?
        var heightColors: LayerHeightColors?
        func updateVisible(_ view: SCNView, _ config: BeadPreview) {
            let count = max(0, min(config.visibleCount ?? config.data.segments.count, config.data.segments.count))
            let clipped = config.segmentFraction < 0.999999 && count > 0
            let completeCount = clipped ? count - 1 : count
            for range in ranges {
                let end = range.ends[min(completeCount, range.ends.count - 1)]
                range.node.isHidden = end == 0
                range.element.primitiveRange = NSRange(location: 0, length: end)
            }
            partial?.removeFromParentNode()
            partial = nil
            if clipped, !ranges.isEmpty {
                let node = BeadMesh.build(
                    config.data, config.zLimit, config.showTravel, false, config.mode,
                    end: count, fraction: config.segmentFraction, asLines: config.asLines,
                    start: count - 1, decorations: false, preparedFrame: cachedFrames?.model,
                    preparedColors: heightColors)
                updateBackground(node)
                view.scene?.rootNode.addChildNode(node)
                partial = node
            }
            (view as? ZoomSceneView)?.requestFrame()
        }

        let queue = DispatchQueue(label: "149.Slicer.bead.mesh", qos: .userInitiated)
        func update(_ view: SCNView, _ config: BeadPreview) {
            latest = config
            if cachedFrames?.sha != config.data.sha256 {
                cachedFrames = (
                    config.data.sha256, BeadMesh.frame(config.data, true), BeadMesh.frame(config.data, false)
                )
            }
            let frame = cachedFrames!.model
            (view as? ZoomSceneView)?.panMode = config.panMode
            (view as? ZoomSceneView)?.zoomChanged = { value in config.zoom = value }
            let mf = cachedFrames!.model
            let nextCameraKey = config.data.sha256
            if let viewport = view as? ZoomSceneView {
                viewport.synchronizeZoom(
                    config.sharedCamera?.valid == true && config.sharedCamera?.action == config.viewAction
                        ? config.sharedCamera!.magnification : config.zoom)
                if cameraKey != nextCameraKey || action != config.viewAction {
                    let newModel = cameraKey != nextCameraKey
                    cameraKey = nextCameraKey
                    action = config.viewAction
                    let command = newModel ? 0 : action % 10
                    if command == 6 {
                        let center = SCNVector3(
                            Float(config.data.bedSize[0] / 2 - mf.cx), Float(-mf.cz),
                            Float(-(config.data.bedSize[1] / 2 - mf.cy)))
                        viewport.frameTarget(
                            center,
                            extent: SIMD3(
                                Float(config.data.bedSize[0] * 1.04), Float(max(1, config.data.height)),
                                Float(config.data.bedSize[1] * 1.04)), orientation: 5)
                    } else {
                        viewport.frameTarget(
                            mf.center, extent: SIMD3(Float(mf.sx), Float(mf.sz), Float(mf.sy)),
                            orientation: command == 2 ? nil : command)
                    }
                }
                viewport.applyScale()
            }
            if nozzle == nil {
                let marker = SCNNode()
                marker.name = "nozzle-marker"
                let nozzleScale: CGFloat =
                    config.data.machine_name == "G1" || config.data.machine_name == nil ? 1 : 0.35
                let cone = SCNCone(topRadius: 4, bottomRadius: 0.65, height: 5)
                marker.scale = SCNVector3(Float(nozzleScale), Float(nozzleScale), Float(nozzleScale))
                let material = SCNMaterial()
                material.diffuse.contents = NSColor(red: 0.76, green: 0.64, blue: 0.37, alpha: 1)
                material.specular.contents = NSColor.white
                material.shininess = 75
                cone.materials = [material]
                let tip = SCNNode(geometry: cone)
                tip.position.y = 2.5
                marker.addChildNode(tip)
                let hexagon = SCNCylinder(radius: 4.6, height: 3)
                hexagon.radialSegmentCount = 6
                let body = SCNNode(geometry: hexagon)
                body.geometry?.materials = [material]
                body.position.y = 6.5
                marker.addChildNode(body)
                let neck = SCNNode(geometry: SCNCylinder(radius: 2.6, height: 4))
                neck.geometry?.materials = [material]
                neck.position.y = 10
                marker.addChildNode(neck)
                nozzle = marker
                view.scene?.rootNode.addChildNode(marker)
            }
            nozzle?.isHidden = config.nozzlePoint == nil
            if let p = config.nozzlePoint {
                nozzle?.position = SCNVector3(Float(p[0] - frame.cx), Float(p[2] - frame.cz), Float(-(p[1] - frame.cy)))
            }
            (view as? ZoomSceneView)?.requestFrame()
            if whiteBackground != config.backgroundWhite || outlineStrength != config.outlineStrength
                || xray != config.xray || whiteModel != config.whiteModel || xrayStrength != config.xrayStrength
            {
                outlineStrength = config.outlineStrength
                whiteBackground = config.backgroundWhite
                xray = config.xray
                whiteModel = config.whiteModel
                xrayStrength = config.xrayStrength
                if let root = view.scene?.rootNode { updateBackground(root) }
            }
            if let scene = view.scene {
                platform.update(
                    size: config.data.bedSize, origin: SIMD3(frame.cx, frame.cy, frame.cz),
                    visible: config.showBed, tone: background.amount, scene: scene)
            }
            let next =
                config.data.sha256 + config.mode.rawValue + String(config.showTravel)
                + String(config.asLines) + String(config.zLimit)
            if key == next {
                updateVisible(view, config)
                return
            }
            key = next
            revision += 1
            let ticket = revision
            pending?.cancel()
            cancellation.cancel()
            let token = MeshCancellation()
            cancellation = token
            let work = DispatchWorkItem { [weak self, weak view] in
                guard let self, !token.isCancelled else { return }
                let colors = LayerHeightColors(heights: config.mode == .height ? (config.data.layer_heights ?? []) : [])
                var drawRanges = [DrawRange]()
                let node = BeadMesh.build(
                    config.data, config.zLimit, config.showTravel, false, config.mode,
                    asLines: config.asLines, decorations: false, preparedFrame: frame, preparedColors: colors,
                    captureRange: { node, element, ends in
                        drawRanges.append(DrawRange(node: node, element: element, ends: ends))
                    })
                guard !token.isCancelled else { return }
                DispatchQueue.main.async {
                    guard self.revision == ticket, let view else { return }
                    SCNTransaction.begin()
                    SCNTransaction.disableActions = true
                    defer { SCNTransaction.commit() }
                    view.scene?.rootNode.childNode(withName: "beads", recursively: false)?.removeFromParentNode()
                    node.name = "beads"
                    (view as? ZoomSceneView)?.didLoadPreview(config.data.sha256)
                    self.ranges = drawRanges
                    self.heightColors = colors
                    self.updateBackground(node)
                    view.scene?.rootNode.addChildNode(node)
                    self.updateVisible(view, self.latest ?? config)
                    config.onReady?()
                }
            }
            pending = work
            queue.async(execute: work)

        }
    }
}

enum BeadMesh {
    struct Frame {
        let cx: Double
        let cy: Double
        let cz: Double
        let span: Double
        var sx: Double = 1
        var sy: Double = 1
        var sz: Double = 1
        var center = SCNVector3Zero
    }
    static func frame(_ data: PreviewResult, _ bed: Bool) -> Frame {
        let rows = data.segments.filter { Int($0[6]) != 4 }
        let xs = rows.flatMap { [$0[0], $0[3]] }
        let ys = rows.flatMap { [$0[1], $0[4]] }
        let minx = xs.min() ?? 0
        let maxx = xs.max() ?? 1
        let miny = ys.min() ?? 0
        let maxy = ys.max() ?? 1
        let w = data.beads.map { $0[0] }.max() ?? 1
        return Frame(
            cx: data.bedSize[0] / 2, cy: data.bedSize[1] / 2, cz: 0,
            span: bed
                ? max(data.bedSize[0], data.bedSize[1]) * 1.15 : max(maxx - minx + w, maxy - miny + w, data.height, 1),
            sx: maxx - minx + w, sy: maxy - miny + w, sz: max(1, data.height),
            center: SCNVector3(
                (minx + maxx - data.bedSize[0]) / 2, data.height / 2, -(miny + maxy - data.bedSize[1]) / 2))
    }
    static func color(
        _ s: [Double], _ mode: PreviewMode, _ limits: [Double], _ heightColors: LayerHeightColors, _ layerHeight: Double
    ) -> [Float] {
        if mode == .xray { return [0.92, 0.92, 0.92, 1] }
        if mode == .role {
            return previewRoleRGB[Int(s[6])].map { Float($0) } + [1]
        }
        if Int(s[6]) == 4 && mode != .speed { return [0.48, 0.52, 0.57, 1] }
        if mode == .height { return heightColors.color(layerHeight).map { Float($0) } + [1] }
        let span = limits[1] - limits[0]
        let f = span > 1e-7 ? min(1, max(0, (s[mode.index] - limits[0]) / span)) : 0.5
        return previewMetricRGB(f).map { Float($0) } + [1]
    }
    static func build(
        _ data: PreviewResult, _ z: Double, _ travel: Bool, _ bed: Bool, _ mode: PreviewMode, end: Int? = nil,
        fraction: Double = 1, asLines: Bool = false, start: Int = 0, continues: Bool = false, decorations: Bool = true,
        preparedFrame: Frame? = nil, preparedColors: LayerHeightColors? = nil,
        captureRange: ((SCNNode, SCNGeometryElement, [Int]) -> Void)? = nil
    ) -> SCNNode {
        let f = preparedFrame ?? frame(data, false)
        let limits = data.limits(mode, travel)
        let heightColors =
            preparedColors ?? LayerHeightColors(heights: mode == .height ? (data.layer_heights ?? []) : [])
        var vertices = [SCNVector3]()
        var normals = [SCNVector3]()
        var coordinates = [CGPoint]()
        var colors = [Float]()
        var indices = [UInt32]()
        var linePoints = [SCNVector3]()
        var lineColors = [Float]()
        // Join only real, visible extrusion neighbours. Travel, cuts and sharp
        // reversals remain exposed ends; continuous paths have no internal caps.
        let count = max(0, min(end ?? data.segments.count, data.segments.count))
        let connectionLimit = continues ? data.segments.count : count
        func connected(_ left: Int, _ right: Int) -> Bool {
            guard left >= 0, right < connectionLimit, right == left + 1 else { return false }
            let a = data.segments[left]
            let b = data.segments[right]
            guard Int(a[6]) != 4, Int(b[6]) != 4,
                data.beads[left][0] > 0, data.beads[right][0] > 0,
                data.beads[left][1] > 0, data.beads[right][1] > 0,
                max(a[2], a[5], b[2], b[5]) <= z + 1e-7
            else { return false }
            let gap = (0..<3).reduce(0.0) { $0 + pow(a[$1 + 3] - b[$1], 2) }
            let ax = a[3] - a[0]
            let ay = a[4] - a[1]
            let bx = b[3] - b[0]
            let by = b[4] - b[1]
            let lengths = hypot(ax, ay) * hypot(bx, by)
            return gap < 1e-10 && lengths > 1e-12 && (ax * bx + ay * by) / lengths > -0.5
        }
        func jointNormal(_ index: Int, _ nx: Double, _ ny: Double) -> (Double, Double) {
            let row = data.segments[index]
            let dx = row[3] - row[0]
            let dy = row[4] - row[1]
            let length = hypot(dx, dy)
            let x = nx - dy / length
            let y = ny + dx / length
            let k = hypot(x, y)
            return (x / k, y / k)
        }
        func xyz(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
            SCNVector3(Float(x - f.cx), Float(z - f.cz), Float(-(y - f.cy)))
        }
        var triangleEnds = [0]
        var lineEnds = [0]
        var previousEnd: (segment: Int, ring: UInt32, color: [Float])?
        for i in min(max(0, start), count)..<count {
            defer {
                triangleEnds.append(indices.count / 3)
                lineEnds.append(linePoints.count / 2)
            }
            let s = data.segments[i]
            if min(s[2], s[5]) > z + 1e-7 { continue }
            var a = Array(s[0...2])
            var b = Array(s[3...5])
            if i == (end ?? data.segments.count) - 1 {
                for j in 0..<3 { b[j] = a[j] + (b[j] - a[j]) * min(1, max(0, fraction)) }
            }
            if s[5] > z && s[5] > s[2] {
                let t = (z - s[2]) / (s[5] - s[2])
                for j in 0..<3 { b[j] = s[j] + t * (s[j + 3] - s[j]) }
            } else if s[2] > z && s[2] > s[5] {
                let t = (z - s[5]) / (s[2] - s[5])
                for j in 0..<3 { a[j] = s[j + 3] + t * (s[j] - s[j + 3]) }
            }
            let d = hypot(b[0] - a[0], b[1] - a[1])
            if Int(s[6]) == 4 || asLines {
                if Int(s[6]) != 4 || travel {
                    linePoints += [xyz(a[0], a[1], a[2]), xyz(b[0], b[1], b[2])]
                    let rgba = color(s, mode, limits, heightColors, data.displayLayerHeight(i))
                    lineColors += rgba + rgba
                }
                continue
            }
            let w = data.beads[i][0]
            let h = data.beads[i][1]
            if w <= 0 || h <= 0 || d < 1e-9 { continue }
            let nx = -(b[1] - a[1]) / d
            let ny = (b[0] - a[0]) / d
            let rgba = color(s, mode, limits, heightColors, data.displayLayerHeight(i))
            let joinStart = connected(i - 1, i)
            let joinEnd = connected(i, i + 1) && !(i == count - 1 && fraction < 1)
            let startNormal = joinStart ? jointNormal(i - 1, nx, ny) : (nx, ny)
            let endNormal = joinEnd ? jointNormal(i + 1, nx, ny) : (nx, ny)
            // Share identical endpoint rings, retaining path and color boundaries.
            let reuseStart =
                joinStart && previousEnd?.segment == i - 1 && previousEnd?.color == rgba
                && (0..<3).allSatisfy { data.segments[i - 1][$0 + 3] == s[$0] }
            let startRing = reuseStart ? previousEnd!.ring : UInt32(vertices.count)
            var endRing: UInt32 = 0
            // Nozzle Z is the bead's top, not its vertical centre.
            for (endpoint, point) in [a, b].enumerated() {
                if endpoint == 0 && reuseStart { continue }
                if endpoint == 1 { endRing = UInt32(vertices.count) }
                let joined = endpoint == 0 ? joinStart : joinEnd
                let neighbour = endpoint == 0 ? i - 1 : i + 1
                let width = joined ? (w + data.beads[neighbour][0]) / 2 : w
                let height = joined ? (h + data.beads[neighbour][1]) / 2 : h
                let (normalX2, normalY2) = endpoint == 0 ? startNormal : endNormal
                for sample in BeadProfile.samples {
                    let p = BeadProfile.point(sample, width: width, height: height)
                    let miter = joined ? 1 / max(0.5, normalX2 * nx + normalY2 * ny) : 1
                    vertices.append(
                        xyz(point[0] + normalX2 * p.x * miter, point[1] + normalY2 * p.x * miter, point[2] + p.z))
                    normals.append(SCNVector3(normalX2 * p.nx, p.nz, -normalY2 * p.nx))
                    coordinates.append(.zero)
                    colors += rgba
                }
            }
            for face in 0..<BeadProfile.count {
                let i = UInt32(face)
                let j = UInt32((face + 1) % BeadProfile.count)
                indices += [startRing + i, endRing + i, startRing + j, startRing + j, endRing + i, endRing + j]
            }
            for (ring, exposed, direction) in [(startRing, !joinStart, -1.0), (endRing, !joinEnd, 1.0)] where exposed {
                let offset = UInt32(vertices.count)
                let points = Array(vertices[Int(ring)..<Int(ring) + BeadProfile.count])
                let center = points.reduce(SCNVector3Zero) { SCNVector3($0.x + $1.x, $0.y + $1.y, $0.z + $1.z) }
                vertices.append(
                    SCNVector3(
                        center.x / CGFloat(points.count), center.y / CGFloat(points.count),
                        center.z / CGFloat(points.count)))
                normals.append(SCNVector3(ny * direction, 0, nx * direction))
                coordinates.append(.zero)
                colors += rgba
                for point in points {
                    vertices.append(point)
                    normals.append(SCNVector3(ny * direction, 0, nx * direction))
                    coordinates.append(.zero)
                    colors += rgba
                }
                for j in 0..<BeadProfile.count {
                    let a = offset + 1 + UInt32(j)
                    let b = offset + 1 + UInt32((j + 1) % BeadProfile.count)
                    indices += direction < 0 ? [offset, a, b] : [offset, b, a]
                }
            }
            previousEnd = joinEnd ? (i, endRing, rgba) : nil
        }
        let parent = SCNNode()
        if decorations, let lamp = data.lamp_reference, lamp.center.count == 3 {
            var marks = [SCNVector3]()
            for i in 0..<48 where i % 2 == 0 {
                for j in [i, i + 1] {
                    let a = Double(j) * 2 * Double.pi / 48
                    marks.append(
                        xyz(
                            lamp.center[0] + lamp.diameter / 2 * cos(a), lamp.center[1] + lamp.diameter / 2 * sin(a),
                            lamp.center[2]))
                }
            }
            let g = SCNGeometry(
                sources: [SCNGeometrySource(vertices: marks)],
                elements: [SCNGeometryElement(indices: Array(0..<Int32(marks.count)), primitiveType: .line)])
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor(white: 0.85, alpha: 0.9)
            g.materials = [m]
            let reference = SCNNode(geometry: g)
            reference.name = "lamp-reference-no-extrusion"
            parent.addChildNode(reference)
        }
        if !vertices.isEmpty {
            let cdata = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let source = SCNGeometrySource(
                data: cdata, semantic: .color, vectorCount: vertices.count, usesFloatComponents: true,
                componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let mesh = SCNGeometry(
                sources: [
                    SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                    SCNGeometrySource(textureCoordinates: coordinates), source,
                ],
                elements: [element])
            let material = BeadSurface.material(geometricProfile: true)
            material.multiply.contents = NSColor.white
            material.lightingModel = .lambert
            material.isDoubleSided = false
            material.specular.contents = NSColor(white: 0.13, alpha: 1)
            material.shaderModifiers?[.fragment] = ViewportSurfaceShader.outline
            material.setValue(NSNumber(value: 0.0), forKey: "outlineStrength")
            material.setValue(NSNumber(value: 0.933), forKey: "xrayInk")
            material.setValue(NSNumber(value: 1.0), forKey: "xrayColor")
            material.setValue(NSNumber(value: 0.5), forKey: "xrayStrength")
            mesh.materials = [material]
            if mode == .xray {
                material.lightingModel = .constant
                material.specular.contents = NSColor.black
                material.transparencyMode = .singleLayer
                // Match calibration's neutral, rim-weighted X-ray material.
                // Interior faces remain faint; bead silhouettes reveal layer shape.
                material.shaderModifiers = [.fragment: ViewportSurfaceShader.xray]
                material.blendMode = .alpha
                material.name = "slicer-xray"
                material.setValue(NSNumber(value: 0.933), forKey: "xrayInk")
                material.readsFromDepthBuffer = false
                material.writesToDepthBuffer = false
            }

            let body = SCNNode(geometry: mesh)
            body.name = "material-body"
            captureRange?(body, element, triangleEnds)
            parent.addChildNode(body)
        }
        if decorations && bed {
            let bw = data.bedSize[0]
            let bh = data.bedSize[1]
            let step = bw > 500 ? 50.0 : 20.0
            for v in stride(from: 0.0, through: bw, by: step) {
                linePoints += [xyz(v, 0, -0.30), xyz(v, bh, -0.30)]
                for _ in 0..<2 {
                    lineColors += [1, 1, 1, v.truncatingRemainder(dividingBy: step * 2) == 0 ? 0.32 : 0.15]
                }
            }
            for v in stride(from: 0.0, through: bh, by: step) {
                linePoints += [xyz(0, v, -0.30), xyz(bw, v, -0.30)]
                for _ in 0..<2 {
                    lineColors += [1, 1, 1, v.truncatingRemainder(dividingBy: step * 2) == 0 ? 0.32 : 0.15]
                }
            }
            let edgePoints = [xyz(0, 0, -0.25), xyz(bw, 0, -0.25), xyz(bw, bh, -0.25), xyz(0, bh, -0.25)]
            for j in 0..<4 {
                linePoints += [edgePoints[j], edgePoints[(j + 1) % 4]]
                lineColors += [1, 1, 1, 0.65, 1, 1, 1, 0.65]
            }
            func label(_ text: String, _ x: Double, _ y: Double) {
                let shape = SCNText(string: text, extrusionDepth: 0)
                shape.font = NSFont.systemFont(ofSize: CGFloat(min(16, max(4, bw / 62.5))), weight: .medium)
                shape.flatness = 0.5
                let ink = SCNMaterial()
                ink.lightingModel = .constant
                ink.diffuse.contents = NSColor(white: 1, alpha: 0.65)
                shape.materials = [ink]
                let node = SCNNode(geometry: shape)
                node.name = "bed-label"
                node.castsShadow = false
                node.eulerAngles.x = -.pi / 2
                node.position = xyz(x, y, -0.20)
                parent.addChildNode(node)
            }
            label("0", 8, 25)
            label("X · \(Int(bw)) mm", max(20, bw - 180), 25)
            label("Y", 8, max(30, bh - 40))
        }
        if !linePoints.isEmpty {
            let ids = (0..<linePoints.count).map { UInt32($0) }
            let cdata = lineColors.withUnsafeBufferPointer { Data(buffer: $0) }
            let source = SCNGeometrySource(
                data: cdata, semantic: .color, vectorCount: linePoints.count, usesFloatComponents: true,
                componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let geom = SCNGeometry(
                sources: [SCNGeometrySource(vertices: linePoints), source],
                elements: [SCNGeometryElement(indices: ids, primitiveType: .line)])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = NSColor.white
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = decorations && bed ? "bed-lines" : "travel-and-grid"
            captureRange?(node, geom.elements[0], lineEnds)
            node.castsShadow = false
            node.renderingOrder = -1
            parent.addChildNode(node)
        }
        return parent
    }
}

// Fixed studio lights: no animation, no downloaded environment maps.
enum StudioLighting {
    static func install(in scene: SCNScene) {
        let ambient = SCNNode()
        ambient.name = "studio-ambient"
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = NSColor.white
        ambient.light!.intensity = 170
        scene.rootNode.addChildNode(ambient)
        func directional(_ name: String, _ position: SCNVector3, _ intensity: CGFloat, _ shadow: Bool) {
            let node = SCNNode()
            node.name = name
            node.light = SCNLight()
            let light = node.light!
            light.type = .directional
            light.color = NSColor.white
            light.intensity = intensity
            light.castsShadow = shadow
            if shadow {
                light.shadowMode = .deferred
                light.shadowColor = NSColor(white: 0, alpha: 0.22)
                light.shadowRadius = 5
                light.shadowSampleCount = 8
                light.shadowMapSize = CGSize(width: 2048, height: 2048)
                light.orthographicScale = 1800
                light.zNear = 1
                light.zFar = 5000
                light.shadowBias = 0.2
            }
            node.position = position
            node.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(node)
        }
        directional("studio-key", SCNVector3(-700, 1100, 650), 850, false)
        directional("studio-fill", SCNVector3(700, 400, 200), 240, false)
        directional("studio-rim", SCNVector3(100, 700, -900), 500, false)
        // A soft lower fill makes bead contours visible when inspecting the base.
        directional("studio-underside", SCNVector3(-700, -500, 650), 550, false)
    }
}

// Seamless spherical lighting keeps hard light-card edges out of refractive materials.
enum GlassEnvironment {
    static let image: NSImage = {
        let width = 512
        let height = 256
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let key = simd_normalize(SIMD3<Double>(-0.5, 0.45, 0.7))
        let fill = simd_normalize(SIMD3<Double>(0.7, 0.25, -0.4))
        for y in 0..<height {
            let latitude = Double(y) / Double(height - 1) * Double.pi
            for x in 0..<width {
                let longitude = (Double(x) / Double(width - 1) - 0.5) * 2 * Double.pi
                let direction = SIMD3(cos(longitude) * sin(latitude), cos(latitude), sin(longitude) * sin(latitude))
                let light =
                    0.24 + 0.16 * (direction.y + 1) / 2
                    + 0.46 * pow(max(0, simd_dot(direction, key)), 6)
                    + 0.24 * pow(max(0, simd_dot(direction, fill)), 4)
                let value = UInt8(min(1, light) * 255)
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)!
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }()
}

// Cancellation is checked between batches so superseded requests do not queue
// a full model rebuild. Never mutate mounted SceneKit nodes on the worker queue.
final class MeshCancellation {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

// Playback invalidates only the canvas and transport controls, not the parameter forms.
struct SlicePlaybackPreview: View {
    @ObservedObject var model: Workbench
    @ObservedObject var timeline: PathTimeline
    let data: PreviewResult
    let onReady: () -> Void
    var body: some View {
        let cursor = timeline.cursor
        BeadPreview(
            data: data, zLimit: .greatestFiniteMagnitude, showTravel: model.showTravel,
            showBed: model.showBed, mode: model.previewMode, viewAction: model.beadViewAction,
            zoom: $model.previewZoom, visibleCount: cursor.end, segmentFraction: cursor.fraction,
            nozzlePoint: model.showNozzle ? cursor.point : nil, asLines: !model.showBeads,
            panMode: model.panMode, onReady: onReady, sharedCamera: model.sharedCamera,
            outlineStrength: 0,
            backgroundWhite: model.backgroundWhite, xray: false, active: !model.showingModel,
            whiteModel: false, xrayStrength: model.lineStrength, playing: timeline.playing)
    }
}
