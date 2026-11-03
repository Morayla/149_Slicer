import AppKit
import Foundation

struct MaterialAppearance: Codable, Equatable {
    var red = 0.78
    var green = 0.78
    var blue = 0.78
    var roughness = 0.55
    var metallic = 0.0
    var transmission = 0.0
    var ior = 1.5

    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var valid: Bool {
        [red, green, blue, roughness, metallic, transmission].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && ior.isFinite && (1...2.5).contains(ior)
    }
    static func initial(for material: String) -> Self {
        // Optical values are visual estimates, not manufacturer-measured coefficients.
        switch material {
        case "pellet:cafblo_rsd038_4r0001":
            return Self(red: 0.82, green: 0.92, blue: 1, roughness: 0.16, transmission: 0.85, ior: 1.5)
        case "pellet:polymaker_petg1000":
            return Self(red: 0.97, green: 0.98, blue: 1, roughness: 0.18, transmission: 0.84, ior: 1.57)
        default: return Self()
        }
    }
}

extension Workbench {
    var materialIdentity: String {
        isBambu ? "filament:" + (fields["FilamentType"] ?? "PETG") : "pellet:" + (fields["PelletMaterial"] ?? "custom")
    }
    var appearanceStorageKey: String { "149.material.appearance." + materialIdentity }
    func loadMaterialAppearance() {
        if let saved = savedMaterialRecipes.first(where: {
            $0.id == selectedMaterialRecipeID && $0.material == materialIdentity
        }) {
            materialAppearance = saved.appearance
            return
        }
        if let data = preferences.data(forKey: appearanceStorageKey),
            let value = try? JSONDecoder().decode(MaterialAppearance.self, from: data), value.valid
        {
            materialAppearance = value
        } else {
            materialAppearance = .initial(for: materialIdentity)
        }
    }
}
