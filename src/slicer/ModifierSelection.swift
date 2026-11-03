import SwiftUI

extension Workbench {
    var supportsNoise: Bool { ["Cylinder", "Cone"].contains(fields["SourceMode"] ?? "") }
    var supportsMesh: Bool { ["Cylinder", "Ellipse"].contains(fields["SourceMode"] ?? "") }
    var modifierSelection: Binding<String> {
        Binding(
            get: {
                if self.toggle("NoiseEnabled").wrappedValue { return "noise" }
                if self.toggle("MeshEnabled").wrappedValue { return "mesh" }
                return self.toggle("WaveEnabled").wrappedValue ? "wave" : "none"
            },
            set: { value in
                var next = self.fields
                for (key, kind) in [("NoiseEnabled", "noise"), ("WaveEnabled", "wave"), ("MeshEnabled", "mesh")] {
                    next[key] = value == kind ? "1" : "0"
                }
                self.fields = next
                self.dirty = true
            })
    }
}
