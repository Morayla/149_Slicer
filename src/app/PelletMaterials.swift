import Foundation

struct PelletMaterial: Decodable, Identifiable {
    let id: String
    let name: String
    let fields: [String: Double]  // Native UI units: speeds in mm/s.
    let trialFlow: Double?
    let maxTrialSpeed: Double?
}
