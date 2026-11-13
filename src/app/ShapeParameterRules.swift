import Foundation

struct ShapeParameterRule: Decodable {
    let label: String, unit: String, integer: Bool, step: Double
    var minimum: Double?, maximum: Double?
}
enum ShapeParameterRules {
    struct Module: Decodable, Identifiable {
        let id: String, title: String
        let defaults: [String: String]
    }
    struct Catalog: Decodable {
        let version: Int
        let modules: [Module]
        let parameters: [String: ShapeParameterRule]
    }
    static let catalog: Catalog = {
        let url = Bundle.main.url(
            forResource: BundledResource.shapeModules, withExtension: nil, subdirectory: BundledResource.definitions)!
        return try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }()
    static func rule(_ key: String) -> ShapeParameterRule? { catalog.parameters[key] }
}
