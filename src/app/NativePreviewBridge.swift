import Foundation

extension PreviewResult {
    init(native:NativeSliceResult) throws {
        // Decode only the small descriptive fields. Geometry stays in typed
        // Swift arrays, avoiding a full JSON write/read on each fresh slice.
        var metadata=native.metadata;metadata["segments"]=[];metadata["beads"]=[]
        self=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:metadata))
        segments=native.preview.segments;beads=native.preview.beads
        layers=native.preview.layers.map{Layer(start:$0.start,end:$0.end,z:$0.z)}
        layer_heights=native.preview.layerHeights
    }
}
