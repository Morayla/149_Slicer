import Foundation

// File names of the resources the application loads from its bundle.
// scripts/build-app.sh checks every file name quoted in this file against the built bundle,
// so a renamed or missing resource fails the build instead of failing at launch.
enum BundledResource {
    static let appIcon = "app-icon.icns"
    static let previewConfig = "g1-preview-config.txt"

    static let definitions = "definitions"
    static let defaults = "defaults.json"
    static let pelletMaterials = "pellet-materials.json"
    static let shapeModules = "shape-modules.json"
    static let eggScrollProfile = "egg-scroll-profile.json"
    static let fern1060Profile = "fern1060-profile.json"
    static let fern1060EProfile = "fern1060-e-profile.json"
    static let trimmedPipeScrollProfile = "trimmed-pipe-scroll-profile.json"
    static let wardrobeProfile = "wardrobe-profile.json"

    static func definition(_ name: String, in resources: URL) -> URL {
        resources.appendingPathComponent(definitions).appendingPathComponent(name)
    }
}
