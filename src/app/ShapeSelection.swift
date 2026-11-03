import Foundation

extension Workbench {
    func selectShape(_ mode: String) {
        guard mode != fields["SourceMode"],
            let module = ShapeParameterRules.catalog.modules.first(where: { $0.id == mode })
        else { return }
        finishPlacement()
        restorePlacement([:])
        sharedCamera.valid = false
        previewZoom = 1
        rememberShape()
        var next = fields
        if let draft = shapeDrafts[printerModel + ":" + mode] {
            next.merge(draft, uniquingKeysWith: { $1 })
        } else {
            next.merge(module.defaults, uniquingKeysWith: { $1 })
            for key in ["WaveEnabled", "MeshEnabled", "NoiseEnabled", "NoiseZEnabled"] { next[key] = "0" }
        }
        next["SourceMode"] = mode
        fields = next
        dirty = true
    }
}
