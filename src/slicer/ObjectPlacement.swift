import SceneKit
import SwiftUI

enum PlacementTool: String, CaseIterable {
    case move = "移动", rotate = "旋转"
    var symbol: String {
        switch self { case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: return "rotate.right" }
    }
}

struct PlacementCamera {
    let target: SIMD3<Float>, yaw: Float, pitch: Float, distance: Float
    let scale: Double, magnification: Double
    let orientation: Int
    init(_ state: PreviewCameraState, orientation: Int) {
        target = state.target; yaw = state.yaw; pitch = state.pitch; distance = state.distance
        scale = state.scale; magnification = state.magnification; self.orientation = orientation
    }
    func restore(_ state: PreviewCameraState, action: Int) {
        state.target = target; state.yaw = yaw; state.pitch = pitch; state.distance = distance
        state.scale = scale; state.magnification = magnification; state.action = action; state.valid = true
    }
}

extension Workbench {
    var placementCenter: SIMD2<Double> {
        let fixedOrigin = ["Fern1060", "Fern1060E", "TravelTest"].contains(fields["SourceMode"] ?? "")
        let origin = fixedOrigin ? SIMD2(500.0, 500.0)
            : SIMD2(Double(fields["CX"] ?? "500") ?? 500, Double(fields["CY"] ?? "500") ?? 500)
        return origin + placementOffset
    }
    func movePlacement(to center: SIMD2<Double>) {
        placementOffset += center - placementCenter
    }
    var placementValues: [String: Double] {
        ["rotation": placementRotation, "x": placementOffset.x, "y": placementOffset.y]
    }
    func savePlacement() {
        dirty = true
        preferences.set(placementValues, forKey: "149.placement.transform." + printerModel)
        scheduleModelPreview()
    }
    func restorePlacement(_ values: [String: Double]) {
        placementRotation = values["rotation"] ?? 0
        placementOffset = SIMD2(values["x"] ?? 0, values["y"] ?? 0)
    }
    func activatePlacement(_ tool: PlacementTool) {
        guard !busy, modelGeometry != nil else { return }
        if placementTool == tool { finishPlacement(); return }
        if placementTool == nil {
            placementCamera = PlacementCamera(sharedCamera, orientation: cameraOrientation)
            placementBedWasVisible = showBed
            showBed = true
            cameraAction(6)
        }
        placementTool = tool
    }
    func finishPlacement() {
        guard placementTool != nil else { return }
        setInteractivePreview(false)
        if let camera = placementCamera {
            camera.restore(sharedCamera, action: beadViewAction)
            cameraOrientation = camera.orientation
            previewZoom = camera.magnification
        }
        showBed = placementBedWasVisible
        placementTool = nil
        placementCamera = nil
    }
    func dragPlacement(from a: SIMD2<Double>, to b: SIMD2<Double>) {
        switch placementTool {
        case .move:
            placementOffset += b - a
        case .rotate:
            let center = placementCenter - SIMD2(printerBedSize[0] / 2, printerBedSize[1] / 2)
            let u = a - center, v = b - center
            let delta = atan2(u.x * v.y - u.y * v.x, simd_dot(u, v))
            placementRotation += delta * 180 / .pi
        case nil: break
        }
    }
}

struct PlacementToolbar: View {
    @ObservedObject var model: Workbench
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(PlacementTool.allCases, id: \.self) { tool in
                    ViewportIconButton(title: tool.rawValue, symbol: tool.symbol, selected: model.placementTool == tool) {
                        model.activatePlacement(tool)
                    }.disabled(model.modelGeometry == nil || model.busy)
                        .help(L(tool.rawValue))
                        .accessibilityIdentifier("slicer.tool." + String(describing: tool))
                }
            }.padding(2).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            if let tool = model.placementTool {
                VStack(alignment: .leading, spacing: 8) {
                    if tool == .move {
                        HStack(spacing: 4) {
                            field("X", value: Binding(get: { model.placementCenter.x }, set: {
                                model.movePlacement(to: SIMD2($0, model.placementCenter.y))
                            }), unit: "mm")
                            ViewportIconButton(title: "居中", symbol: "scope") {
                                let x = model.printerModel == "H2D"
                                    ? (model.fields["H2DNozzle"] == "Right" ? 187.5 : 162.5) : model.printerBedSize[0] / 2
                                model.movePlacement(to: SIMD2(x, model.printerBedSize[1] / 2))
                            }
                        }
                        HStack(spacing: 4) {
                            field("Y", value: Binding(get: { model.placementCenter.y }, set: {
                                model.movePlacement(to: SIMD2(model.placementCenter.x, $0))
                            }), unit: "mm")
                            finishButton
                        }
                    } else if tool == .rotate {
                        HStack(spacing: 4) { field("Z", value: $model.placementRotation, unit: "°"); finishButton }
                    }
                }.padding(8).frame(width: 196).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }.environment(\.colorScheme, model.backgroundWhite ? .light : .dark)
    }
    private var finishButton: some View {
        ViewportIconButton(title: "完成摆放", symbol: "checkmark") { model.finishPlacement() }
    }
    private func field(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack(spacing: 6) {
            uiText(title).frame(width: 30, alignment: .leading)
            NumericField(title, text: text).frame(width: 76, height: 24)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func field(_ title: String, value: Binding<Double>, unit: String) -> some View {
        field(title, text: Binding(get: { NumericField.format((value.wrappedValue * 100).rounded() / 100) }, set: {
            if let number = Double($0), number.isFinite { value.wrappedValue = number }
        }), unit: unit)
    }
}

enum PlacementRotation {
    static func apply(_ angle: Double, to prepared: NativePreparedModel, offset: SIMD2<Double> = .zero) throws -> NativePreparedModel {
        guard angle != 0 || offset != .zero else { return prepared }
        var shape = prepared.shape
        let records = try SliceGcode.records(shape.gcode).0
        var low = SIMD2<Double>(repeating: .infinity), high = SIMD2<Double>(repeating: -.infinity)
        for r in records where r.deposits {
            if let p = r.after.point { low = simd_min(low, SIMD2(p.x, p.y)); high = simd_max(high, SIMD2(p.x, p.y)) }
        }
        let center = try SIMD2(SliceGcode.metadata(shape.gcode, "PLACEMENT_CENTER_X", (low.x + high.x) / 2),
            SliceGcode.metadata(shape.gcode, "PLACEMENT_CENTER_Y", (low.y + high.y) / 2))
        let a = angle * .pi / 180, c = cos(a), s = sin(a)
        func rotate(_ p: SlicePoint) -> SlicePoint {
            let x = p.x - center.x, y = p.y - center.y
            return SlicePoint(center.x + offset.x + x * c - y * s, center.y + offset.y + x * s + y * c, p.z)
        }
        var lines = SliceGcode.lines(shape.gcode)
        for r in records {
            var hasXY = false
            SliceGcode.readWords(lines[r.line]) { axis, _ in if axis == 88 || axis == 89 { hasXY = true } }
            guard hasXY, let x = r.after.x, let y = r.after.y else { continue }
            let p = rotate(SlicePoint(x, y, r.after.z ?? 0))
            lines[r.line] = SliceGcode.word(SliceGcode.word(lines[r.line], "X", p.x), "Y", p.y)
        }
        shape.gcode = SliceGcode.setMeta(SliceGcode.setMeta(lines.joined(separator: "\n"), "PLACEMENT_CENTER_X",
            SliceGcode.fmt(center.x)), "PLACEMENT_CENTER_Y", SliceGcode.fmt(center.y))
        if let raw = SliceGcode.meta(shape.gcode, "G1_FINISH_CANDIDATE") {
            var candidate = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
            let points = candidate["points"] as! [[Double]]
            candidate["points"] = points.map { point in
                let p = rotate(SlicePoint(point[0], point[1], point[2]))
                return [p.x, p.y, p.z]
            }
            let json = try JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys])
            shape.gcode = SliceGcode.setMeta(shape.gcode, "G1_FINISH_CANDIDATE", String(decoding: json, as: UTF8.self))
        }
        shape.points = shape.points.map(rotate); shape.wall = shape.wall.map(rotate)
        shape.bottoms = shape.bottoms.map { $0.map(rotate) }
        return NativePreparedModel(key: prepared.key, shape: shape)
    }
    static func generate(_ raw: [String: Any], engine: NativeSliceEngine, prepared: NativePreparedModel?) throws -> NativeSliceResult {
        let placement = raw["placement"] as? [String: Double] ?? [:]
        let angle = placement["rotation"] ?? 0
        let offset = SIMD2(placement["x"] ?? 0, placement["y"] ?? 0)
        guard angle != 0 || offset != .zero else { return try engine.generate(raw, prepared: prepared) }
        let original = try prepared ?? engine.prepareModel(raw)
        let result = try engine.generate(raw, prepared: apply(angle, to: original, offset: offset))
        return NativeSliceResult(gcode: result.gcode, project: result.project, preview: result.preview,
            metadata: result.metadata, bambu: result.bambu, model: original.shape, modelKey: original.key)
    }
}
