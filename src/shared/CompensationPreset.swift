import Foundation

struct CompensationPreset: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var fields: [String: String]
}
