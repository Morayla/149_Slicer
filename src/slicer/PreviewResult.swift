import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PreviewResult: Codable {
    struct WaveFit: Codable {
        let requested: Double
        let effective: Double
        let kind: String
    }
    let wave_fit: WaveFit?
    struct MeshFit: Codable {
        let requested: Double
        let effective: Double
        let opening: Double
        let pitch: Double
        let turns: Int
    }
    let mesh_fit: MeshFit?
    struct NoiseFit: Codable {
        let requested: Double
        let effective: Double
        let scale: Double
        let z_effective: Double?
    }
    let noise_fit: NoiseFit?
    struct LampReference: Codable {
        let center: [Double]
        let diameter: Double
    }
    let lamp_reference: LampReference?
    struct Layer: Codable {
        let start: Int
        let end: Int
        let z: Double
    }
    struct FlowReport: Codable {
        let requested_peak: Double
        let effective_peak: Double
        let limited_segments: Int
        let limit: Double
    }
    let flow_report: FlowReport?
    var layers: [Layer]? = nil
    var layer_heights: [Double]? = nil
    func displayLayerHeight(_ index: Int) -> Double {
        guard let heights = layer_heights, index >= 0, index < heights.count else { return 0 }
        return heights[index]
    }
    struct Summary: Codable {
        struct Assembly: Codable {
            let mass_g: Double
            let part_count: Int
            let parts_g: [Double]
            let scope: String
            let method: String
            let estimated: Bool
            let motion_minutes: Double?
        }
        let assembly: Assembly?
        let segments: Int
        let volume_mm3: Double
        let path_mm: Double
        let motion_minutes: Double
        let compute_seconds: Double
        let model_dimensions_mm: [Double]?
        let mass_g: Double
        let model_mass_g: Double
        let skirt_mass_g: Double
        let extra_mass_g: Double
        let density_g_cm3: Double
    }
    let bed_size: [Double]?
    let machine_name: String?
    var bedSize: [Double] { bed_size ?? [1000, 1000, 1000] }
    let ok: Bool
    let preview_schema: Int
    let ranges: [String: [Double]]
    var segments: [[Double]]
    var beads: [[Double]]
    let sha256: String
    let height: Double
    let summary: Summary
    let info: String
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case xray = "X-ray"
    case role = "路径类型"
    case flow = "体积流量"
    case height = "层高"
    case speed = "速度"
    var id: String { rawValue }
    var index: Int {
        switch self {
        case .flow: return 7
        case .height: return 8
        case .speed: return 9
        case .role, .xray: return 6
        }
    }
    var unit: String {
        switch self {
        case .flow: return "mm³/s"
        case .height: return "mm"
        case .speed: return "mm/s"
        case .role, .xray: return ""
        }
    }
    var detail: String {
        switch self {
        case .xray: return "透视轮廓与逐层料道。"
        case .role: return "颜色区分裙边、底部、墙体与收尾。"
        case .flow: return "指令体积流量 = E ÷ 该段运动时间，包含流量倍率；不是实测出料量。"
        case .height: return "按首层、底部和墙体的打印层高分色；螺旋起步与收尾的局部挤出间隙不单独分档。可变层高按整层或整圈的规划层高显示。"
        case .speed: return "显示 F 指定的路径速度，不含固件加减速；勾选空移可比较移动速度。"
        }
    }
    func label(_ value: Double) -> String {
        if value != 0 && abs(value) < 0.001 { return String(format: "%.1e", value) }
        return String(format: self == .height ? "%.3f" : "%.2f", value)
    }
}

func metricColor(_ fraction: Double) -> Color {
    let rgb = previewMetricRGB(fraction)
    return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
}

extension PreviewResult {
    func limits(_ mode: PreviewMode, _ showTravel: Bool) -> [Double] {
        let key = mode == .flow ? "flow" : mode == .height ? "layer_height" : "all_speed"
        return ranges[key] ?? [0, 0]
    }
}
