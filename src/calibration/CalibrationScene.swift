import SceneKit
import SwiftUI
import simd

final class CalibrationRenderer {
    let scene = SCNScene(), camera = SCNNode(), assembly = SCNNode(), specimen = SCNNode(), fixture = SCNNode(),
        highlight = SCNNode()
    private var templates: SCNNode?, metadata: [String: [String: Any]] = [:], measurement: SCNNode?, bottom: SCNNode?
    private var lastConfig: CalibrationConfig?, lastStyle = "", lastDevice: Bool?, lastPose: Double = .nan,
        lastCamera = ""
    private var styledNodes: [SCNNode] = []
    private var light = SCNNode()
    private(set) var loaded = false
    weak var view: SCNView?
    func load(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let url = Bundle.main.url(forResource: "calibration", withExtension: "scn.lzfse"),
                    let meta = Bundle.main.url(forResource: "calibration", withExtension: "metadata.json")
                else { throw calibrationError("找不到原生校准模型") }
                let archive = try NSData(contentsOf: url).decompressed(using: .lzfse)
                guard let source = SCNSceneSource(data: archive as Data, options: nil) else {
                    throw calibrationError("原生校准模型格式无效")
                }
                let model = try source.scene(options: nil)
                let data =
                    (try JSONSerialization.jsonObject(with: Data(contentsOf: meta))) as? [String: [String: Any]] ?? [:]
                DispatchQueue.main.async {
                    self.templates = model.rootNode
                    self.metadata = data
                    self.install()
                    self.loaded = true
                    completion(.success(()))
                }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    private func install() {
        scene.rootNode.addChildNode(assembly)
        assembly.addChildNode(specimen)
        assembly.addChildNode(fixture)
        assembly.addChildNode(highlight)
        for name in ["base", "measurement", "bottom"] {
            if let original = templates?.childNode(withName: name, recursively: false) {
                let node = original.clone()
                assembly.addChildNode(node)
                if name == "measurement" { measurement = node }
                if name == "bottom" {
                    bottom = node
                    node.isHidden = true
                }
            }
        }
        // Keep the original bracket and fastening geometry, in millimetres.
        for sign: Float in [-1, 1] {
            if let geometry = templates?.childNode(withName: "printed-bracket", recursively: false)?.geometry?.copy()
                as? SCNGeometry
            {
                let bracket = SCNNode(geometry: geometry)
                bracket.position = SCNVector3(sign * 30, 0, sign == 1 ? -30 : 0)
                bracket.eulerAngles.y = sign == 1 ? 0 : .pi
                assembly.addChildNode(bracket)
            }
            for h: Float in [15, 45] {
                if let geometry = templates?.childNode(withName: "printed-bracket-screw", recursively: false)?.geometry
                {
                    let bottom = SCNNode(geometry: geometry)
                    bottom.eulerAngles.x = -.pi / 2
                    bottom.position = SCNVector3(sign * (30 + h), 4.85, -15)
                    assembly.addChildNode(bottom)
                    let bottomNut = SCNNode(geometry: SCNBox(width: 16, height: 4, length: 12, chamferRadius: 0))
                    bottomNut.position = SCNVector3(sign * (30 + h), -5, -15)
                    assembly.addChildNode(bottomNut)
                    let side = SCNNode(geometry: geometry)
                    side.eulerAngles.y = CGFloat(sign) * .pi / 2
                    side.position = SCNVector3(sign * 34.85, h, -15)
                    assembly.addChildNode(side)
                    let sideNut = SCNNode(geometry: SCNBox(width: 4, height: 16, length: 12, chamferRadius: 0))
                    sideNut.position = SCNVector3(sign * 25, h, -15)
                    assembly.addChildNode(sideNut)
                }
            }
        }
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zNear = 0.5
        camera.camera?.zFar = 4000
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 150
        ambient.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambient)
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.intensity = 600
        light.light?.castsShadow = true
        light.light?.shadowMode = .deferred
        light.light?.shadowSampleCount = 8
        light.light?.shadowRadius = 3
        light.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.light?.orthographicScale = 700
        light.light?.zNear = 1
        light.light?.zFar = 3000
        light.position = SCNVector3(-450, 850, 600)
        light.look(at: SCNVector3(0, 140, 200))
        scene.rootNode.addChildNode(light)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 70
        fill.position = SCNVector3(700, 300, -300)
        fill.look(at: SCNVector3(0, 140, 200))
        scene.rootNode.addChildNode(fill)
    }
    func setActive(_ value: Bool) {
        view?.isPlaying = false
        view?.rendersContinuously = false
        view?.isHidden = !value
        if value { view?.needsDisplay = true }
    }
    func update(_ store: CalibrationStore, dark: Bool) {
        guard loaded, store.active else { return }
        var changed = false
        let device = store.workspace == .device
        if lastDevice != device {
            measurement?.isHidden = device
            bottom?.isHidden = !device
            lastDevice = device
            lastPose = .nan
            changed = true
        }
        var configuration = store.simulation.config
        if device {
            configuration.foot = 0
            configuration.noise = 0
        }
        if lastConfig != configuration {
            rebuild(configuration)
            prepareDetails()
            lastConfig = configuration
            lastStyle = ""
            changed = true
        }
        let style = "\(store.sceneMode):\(store.xrayWhite):\(store.lineStrength):\(store.grain):\(dark)"
        if lastStyle != style {
            applyStyle(
                mode: store.sceneMode, white: store.xrayWhite, strength: store.lineStrength, grain: store.grain,
                dark: dark)
            lastStyle = style
            changed = true
        }
        for stage in [measurement, bottom].compactMap({ $0 }) {
            for node in stage.childNodes {
                let info = metadata[node.name ?? ""] ?? [:]
                let hidden =
                    (info["electronicsPart"] as? Bool == true && !store.electronicsVisible)
                    || (info["electronicsCable"] as? Bool == true && !store.wiresVisible)
                if node.isHidden != hidden {
                    node.isHidden = hidden
                    changed = true
                }
                if info["cover"] as? Bool == true {
                    let x: CGFloat = store.electronicsOpen ? 85 : 0
                    if node.position.x != x {
                        node.position = SCNVector3(x, 0, store.electronicsOpen ? -20 : 0)
                        changed = true
                    }
                }
            }
        }
        if device {
            let position =
                store.homed
                ? (store.status["position"] as? Double).map {
                    ($0 + (metadata["limits"]?["pressedPosition"] as? Double ?? 6.559221918231924)) - 20
                } ?? 0 : 0
            if lastPose != position {
                bottom?.childNodes.filter { metadata[$0.name ?? ""]?["moving"] as? Bool == true }.forEach {
                    $0.position.y = CGFloat(position)
                }
                lastPose = position
                changed = true
            }
            if !highlight.isHidden {
                highlight.isHidden = true
                changed = true
            }
        } else {
            let position = max(0, min(107.8, store.currentHeight - 104.626407107)) - 20
            if lastPose != position {
                measurement?.childNodes.filter { metadata[$0.name ?? ""]?["moving"] as? Bool == true }.forEach {
                    $0.position.y = CGFloat(position)
                }
                updateEndstop(position + 20)
                lastPose = position
                changed = true
            }
            if highlight.isHidden {
                highlight.isHidden = false
                changed = true
            }
            if highlight.position.y != CGFloat(store.currentHeight) {
                highlight.position.y = CGFloat(store.currentHeight)
                changed = true
            }
            let radius = configuration.diameter / 2
            let scale =
                (radius + configuration.radialError(at: store.currentHeight) + 0.25)
                / (radius + configuration.foot + 0.6)
            highlight.scale = SCNVector3(scale, 1, scale)
            if changed, let needle = measurement?.childNode(withName: "REF_Indicator_06", recursively: false) {
                let pivot = SIMD3<Float>(0, 138.4, 60)
                let q = simd_quatf(angle: Float(store.currentError ?? 0) * 2 * .pi, axis: [0, 1, 0])
                needle.simdOrientation = q
                needle.simdPosition = pivot - q.act(pivot) + SIMD3(0, Float(position), 0)
            }

        }
        if lastCamera != store.cameraView {
            lastCamera = store.cameraView
            fit(store.cameraView)
        }
        if changed { view?.needsDisplay = true }
    }
    private func updateEndstop(_ position: Double) {
        guard let lever = measurement?.childNode(withName: "REF_Endstop_Lever", recursively: false) else { return }
        let spec = metadata["endstop"]!
        let samples = spec["samples"] as! [[Double]]
        let p = min(samples.last![0], max(samples[0][0], position))
        let index = samples.indices.dropFirst().first { p <= samples[$0][0] }!
        let a = samples[index - 1]
        let b = samples[index]
        let angle = a[1] + (b[1] - a[1]) * (p - a[0]) / (b[0] - a[0])
        let source = spec["pivot"] as! [Double]
        let pivot = SIMD3<Float>(Float(source[0]), Float(source[2]), Float(source[1]))
        let rotation = simd_quatf(angle: Float(angle), axis: [1, 0, 0])
        lever.simdOrientation = rotation
        lever.simdPosition = pivot - rotation.act(pivot)
    }
    private func rebuild(_ c: CalibrationConfig) {
        specimen.childNodes.forEach { $0.removeFromParentNode() }
        fixture.childNodes.forEach { $0.removeFromParentNode() }
        let center = 124.1 + c.diameter / 2
        specimen.position = SCNVector3(0, 0, center)
        let node = SCNNode(geometry: Self.specimenGeometry(c))
        node.name = "specimen"
        specimen.addChildNode(node)
        func contour(_ y: Double, _ r: Double, _ name: String) {
            let points = (0...160).map { i -> SCNVector3 in
                let a = Double(i) * 2 * .pi / 160
                return SCNVector3(r * cos(a), y, r * sin(a))
            }
            let edges = (0..<Int32(160)).flatMap { [$0, $0 + 1] }
            let line = SCNNode(
                geometry: SCNGeometry(
                    sources: [SCNGeometrySource(vertices: points)],
                    elements: [SCNGeometryElement(indices: edges, primitiveType: .line)]))
            line.name = name
            line.renderingOrder = 3
            specimen.addChildNode(line)
        }
        for y in [0.0, c.height] {
            contour(y + 0.025, c.diameter / 2 + c.radialError(at: y) - 0.28 * c.step, "specimen-contour")
            contour(y + 0.025, c.diameter / 2 - c.lineWidth + 0.28 * c.step, "specimen-contour")
        }
        for layer in 0..<Int(ceil(c.height / c.step)) {
            let y = c.height - (Double(layer) + 0.5) * c.step
            if y >= 0 { contour(y, c.diameter / 2 + c.radialError(at: y) + 0.06, "layer-contour") }
            contour(
                min(c.height, (Double(layer) + 0.5) * c.step), c.diameter / 2 - c.lineWidth - 0.06, "specimen-contour")
        }
        let radius = c.diameter / 2
        for sign: Double in [-1, 1] {
            if let original = templates?.childNode(withName: "sculpted-clamp", recursively: false)?.geometry {
                let jaw = SCNNode(geometry: Self.warpJaw(original, diameter: c.diameter))
                jaw.name = "clamp"
                jaw.eulerAngles.x = -.pi / 2
                if sign == 1 { jaw.simdOrientation = jaw.simdOrientation * simd_quatf(angle: .pi, axis: [0, 0, 1]) }
                jaw.position = SCNVector3(0, 0, center + sign * (radius + 1))
                fixture.addChildNode(jaw)
                let path = NSBezierPath()
                let width = 55.0
                func front(_ x: Double, _ r: Double) -> Double { sqrt(max(0, r * r - x * x)) - r }
                path.move(to: NSPoint(x: -width, y: front(-width, radius)))
                for i in 1...96 {
                    let x = -width + 2 * width * Double(i) / 96
                    path.line(to: NSPoint(x: x, y: front(x, radius)))
                }
                for i in (0...96).reversed() {
                    let x = -width + 2 * width * Double(i) / 96
                    path.line(to: NSPoint(x: x, y: front(x, radius + 1) + 1))
                }
                path.close()
                let pad = SCNNode(geometry: SCNShape(path: path, extrusionDepth: 25))
                pad.orientation = jaw.orientation
                pad.position = SCNVector3(0, 12.5, center + sign * radius)
                fixture.addChildNode(pad)
            }
            for x: Double in [-45, 45] {
                if let geometry = templates?.childNode(withName: "clamp-button-screw", recursively: false)?.geometry {
                    let screw = SCNNode(geometry: geometry)
                    screw.eulerAngles.x = -.pi / 2
                    screw.position = SCNVector3(x, 9.6, center + sign * (radius + 23.5))
                    fixture.addChildNode(screw)
                    let washer = SCNNode(geometry: SCNTube(innerRadius: 3.2, outerRadius: 6.25, height: 1.6))
                    washer.position = SCNVector3(x, 8.8, center + sign * (radius + 23.5))
                    fixture.addChildNode(washer)
                    let nut = SCNNode(geometry: SCNBox(width: 12, height: 4, length: 16, chamferRadius: 0))
                    nut.position = SCNVector3(x, -5, center + sign * (radius + 23.5))
                    fixture.addChildNode(nut)
                }
            }
        }
        let ring = SCNTorus(ringRadius: radius + c.foot + 0.6, pipeRadius: 0.85)
        ring.ringSegmentCount = 160
        ring.pipeSegmentCount = 8
        highlight.geometry = ring
        highlight.position = SCNVector3(0, c.height, center)
        highlight.renderingOrder = 6
        highlight.childNodes.forEach { $0.removeFromParentNode() }
        for (radius, opacity) in [(1.6, 0.2), (3.2, 0.065)] {
            let halo = SCNNode(geometry: SCNTorus(ringRadius: c.diameter / 2 + c.foot + 0.6, pipeRadius: radius))
            halo.name = "highlight-halo"
            halo.opacity = opacity
            halo.renderingOrder = 5
            highlight.addChildNode(halo)
        }
    }
    private static func warpJaw(_ original: SCNGeometry, diameter: Double) -> SCNGeometry {
        guard let source = original.sources(for: .vertex).first else { return original }
        var points = [SCNVector3]()
        points.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { raw in
            for i in 0..<source.vectorCount {
                let offset = source.dataOffset + i * source.dataStride
                let x = Double(raw.loadUnaligned(fromByteOffset: offset, as: Float.self))
                let y = Double(raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self))
                let z = Double(raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
                let old = sqrt(max(0, 101 * 101 - x * x)) - 101
                let radius = diameter / 2 + 1
                let new = sqrt(max(0, radius * radius - x * x)) - radius
                let weight = max(0, min(1, (5 - y) / (5 - old)))
                points.append(SCNVector3(x, y + weight * (new - old), z))
            }
        }
        // Recompute normals after deforming the actual CAD jaw, retaining all holes and ribs.
        return mesh(points: points, indices: indices(original))
    }
    private static func indices(_ geometry: SCNGeometry) -> [Int32] {
        guard let element = geometry.elements.first else { return [] }
        let data = element.data
        return data.withUnsafeBytes { raw in
            (0..<element.primitiveCount * 3).map { i in
                Int32(bitPattern: raw.loadUnaligned(fromByteOffset: i * element.bytesPerIndex, as: UInt32.self))
            }
        }
    }
    static func mesh(points: [SCNVector3], indices: [Int32]) -> SCNGeometry {
        var normals = [SIMD3<Float>](repeating: .zero, count: points.count)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[i])
            let b = Int(indices[i + 1])
            let c = Int(indices[i + 2])
            let n = simd_cross(
                SIMD3<Float>(points[b]) - SIMD3<Float>(points[a]), SIMD3<Float>(points[c]) - SIMD3<Float>(points[a]))
            normals[a] += n
            normals[b] += n
            normals[c] += n
        }
        let vertices = SCNGeometrySource(vertices: points)
        let normal = SCNGeometrySource(
            normals: normals.map {
                let n = simd_length_squared($0) > 1e-12 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0)
                return SCNVector3(n)
            })
        return SCNGeometry(
            sources: [vertices, normal], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
    static func specimenGeometry(
        _ c: CalibrationConfig, firstLayer: Int = 1, lastLayer: Int? = nil, errorAtHeight: ((Double) -> Double)? = nil
    ) -> SCNGeometry {
        var outer: [SIMD2<Double>] = []
        var inner: [SIMD2<Double>] = []
        let count = lastLayer ?? Int(ceil(c.height / c.step))
        let radius = c.diameter / 2
        let segments = 160
        for layer in (firstLayer...count).reversed() {
            let bottom = max(0, c.height - Double(layer) * c.step)
            let top = c.height - Double(layer - 1) * c.step
            let h = top - bottom
            for j in 0...10 {
                let a = Double(j) * Double.pi / 10
                let y = bottom + h / 2 - h / 2 * cos(a)
                let bead = 0.28 * h * (sin(a) - 1)
                outer.append([radius + (errorAtHeight?(y) ?? c.radialError(at: y)) + bead, y])
                inner.append([radius - c.lineWidth - bead, y])
            }
        }
        var profile = outer + inner.reversed()
        profile.append(profile[0])
        var vertices = [SCNVector3]()
        var indices = [Int32]()
        vertices.reserveCapacity(profile.count * (segments + 1))
        indices.reserveCapacity((profile.count - 1) * segments * 6)
        for point in profile {
            for j in 0...segments {
                let angle = Double(j) * 2 * .pi / Double(segments)
                vertices.append(SCNVector3(point.x * cos(angle), point.y, point.x * sin(angle)))
            }
        }
        for i in 0..<profile.count - 1 {
            for j in 0..<segments {
                let a = Int32(i * (segments + 1) + j)
                let b = a + Int32(segments + 1)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        return mesh(points: vertices, indices: indices)
    }
    private func prepareDetails() {
        styledNodes.removeAll(keepingCapacity: true)
        assembly.enumerateChildNodes { node, _ in
            if let geometry = node.geometry, geometry.elements.first?.primitiveType == .triangles,
                node !== self.highlight, node.name != "highlight-halo", node.name != "cad-silhouette"
            {
                self.styledNodes.append(node)
            }
        }
        for node in styledNodes where node.name != "specimen" {
            if node.childNode(withName: "cad-outline", recursively: false) == nil {
                let edge = SCNNode(geometry: CalibrationEdges.geometry(node.geometry!))
                edge.name = "cad-outline"
                node.addChildNode(edge)
            }
            if node.childNode(withName: "cad-silhouette", recursively: false) == nil {
                let silhouette = SCNNode(geometry: node.geometry!.copy() as? SCNGeometry)
                silhouette.name = "cad-silhouette"
                silhouette.renderingOrder = 1
                node.addChildNode(silhouette)
            }
        }
    }

    private func applyStyle(mode: String, white: Bool, strength: Double, grain: Double, dark: Bool) {
        let xray = mode == "xray"
        let lines = mode == "lines"
        let ink = NSColor(white: xray && white ? 23.0 / 255 : 238.0 / 255, alpha: 1)
        scene.background.contents =
            xray
            ? (white ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.045, alpha: 1))
            : lines ? NSColor(white: 0.10, alpha: 1) : NSColor.clear
        light.light?.castsShadow = mode == "clay"
        let clay = CalibrationMaterials.clay(grain: grain)
        let drawing = CalibrationMaterials.ink()
        let outline = CalibrationMaterials.constant(
            NSColor(red: 228.0 / 255, green: 225.0 / 255, blue: 220.0 / 255, alpha: 1), opacity: 0.55 + 0.45 * strength)
        outline.writesToDepthBuffer = false
        let silhouette = CalibrationMaterials.constant(NSColor(white: 21.0 / 255, alpha: 1))
        silhouette.cullMode = .front
        silhouette.writesToDepthBuffer = false
        silhouette.shaderModifiers = [.geometry: "_geometry.position.xyz += _geometry.normal * 0.24;"]
        var xrays: [Double: SCNMaterial] = [:]
        var xrayEdges: [Double: SCNMaterial] = [:]
        for node in styledNodes {
            let flags = metadata[node.name ?? ""] ?? [:]
            let weight: Double =
                flags["electronicsCable"] as? Bool == true || flags["cameraRibbon"] as? Bool == true
                ? (white ? 0.10 : 0.18)
                : flags["electronicsPart"] as? Bool == true || (node.name ?? "").contains("Motor")
                    ? (white ? 0.24 : 0.35) : 1
            let surface = node.name == "specimen" ? 2.1 : 1.0
            let key = weight * surface
            if xrays[key] == nil {
                xrays[key] = CalibrationMaterials.xray(white: white, strength: strength * weight, surface: surface)
            }
            if xrayEdges[weight] == nil {
                xrayEdges[weight] = CalibrationMaterials.constant(ink, opacity: 0.25 * strength * weight, depth: false)
            }
            node.geometry?.materials = [lines ? drawing : xray ? xrays[key]! : clay]
            node.castsShadow = mode == "clay"
            if let edge = node.childNode(withName: "cad-outline", recursively: false) {
                edge.isHidden = !lines && !xray
                edge.renderingOrder = 2
                edge.geometry?.materials = [xray ? xrayEdges[weight]! : outline]
            }
            if let shell = node.childNode(withName: "cad-silhouette", recursively: false) {
                shell.isHidden = !lines
                shell.geometry?.materials = [silhouette]
            }
        }
        for node in specimen.childNodes where node.name?.hasSuffix("contour") == true {
            let layer = node.name == "layer-contour"
            node.isHidden = !layer && !lines && !xray
            node.geometry?.materials = [
                CalibrationMaterials.constant(
                    ink,
                    opacity: layer
                        ? (lines ? 0.55 + 0.4 * strength : xray ? 1.15 * strength : 0.22)
                        : lines ? 0.9 : 0.35 * strength, depth: !xray)
            ]
        }
        highlight.geometry?.materials = [CalibrationMaterials.constant(ink, depth: false)]
        for halo in highlight.childNodes {
            halo.isHidden = lines
            halo.geometry?.materials = [CalibrationMaterials.constant(ink, depth: false)]
        }
    }
    func fit(_ mode: String = "iso") {
        guard loaded else { return }
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        func include(_ node: SCNNode) {
            guard !node.isHidden, node !== highlight, node.name != "cad-silhouette" else { return }
            if let geometry = node.geometry, geometry.elements.first?.primitiveType == .triangles {
                let (low, high) = geometry.boundingBox
                for x in [low.x, high.x] {
                    for y in [low.y, high.y] {
                        for z in [low.z, high.z] {
                            let point = node.simdConvertPosition(SIMD3<Float>(Float(x), Float(y), Float(z)), to: nil)
                            minimum = simd_min(minimum, point)
                            maximum = simd_max(maximum, point)
                        }
                    }
                }
            }
            node.childNodes.forEach(include)
        }
        include(assembly)
        let center = (minimum + maximum) / 2
        let direction: SIMD3<Float> =
            mode == "front"
            ? [0, 0, 1] : mode == "side" ? [-1, 0, 0] : mode == "top" ? [0, 1, 0.0001] : [-1, 0.75, 0.65]
        camera.simdPosition = center + simd_normalize(direction) * 1200
        camera.look(at: SCNVector3(center), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        let size = view?.bounds.size ?? CGSize(width: 800, height: 700)
        let aspect = Float(max(1, size.width) / max(1, size.height))
        var span: Float = 0
        for x in [minimum.x, maximum.x] {
            for y in [minimum.y, maximum.y] {
                for z in [minimum.z, maximum.z] {
                    let point = camera.simdConvertPosition([x, y, z], from: nil)
                    span = max(span, abs(point.y), abs(point.x) / aspect)
                }
            }
        }
        camera.camera?.projectionDirection = .vertical
        camera.camera?.orthographicScale = Double(span * 1.05)
        view?.pointOfView = camera
        view?.defaultCameraController.target = SCNVector3(center)
        view?.needsDisplay = true
    }
    func zoom(_ factor: Double) {
        guard let camera = view?.pointOfView?.camera else { return }
        camera.orthographicScale = max(60, min(900, camera.orthographicScale / factor))
        view?.needsDisplay = true
    }
}
struct NativeCalibrationScene: NSViewRepresentable {
    @AppStorage("previewQuality") private var previewQuality = "detailed"
    @ObservedObject var store: CalibrationStore
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> SCNView {
        let view = CalibrationSceneView(
            frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = store.renderer.scene
        view.pointOfView = store.renderer.camera
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        PreviewQuality.apply(to: view)
        view.rendersContinuously = false
        view.isPlaying = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = false
        store.renderer.view = view
        view.firstLayout = { [weak store] in
            if let store { store.renderer.fit(store.cameraView) }
        }
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        PreviewQuality.apply(to: view)
        store.renderer.update(store, dark: colorScheme == .dark)
        view.isHidden = !store.active
    }
    static func dismantleNSView(_ view: SCNView, coordinator: ()) {
        view.isPlaying = false
        view.scene = nil
    }
}

final class CalibrationSceneView: SCNView {
    var firstLayout: (() -> Void)?
    override func setFrameSize(_ size: NSSize) {
        let needsFit = frame.width <= 0 || frame.height <= 0
        super.setFrameSize(size)
        if needsFit, size.width > 0, size.height > 0 { firstLayout?() }
    }
}
