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
    case xray = "X 光"
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
        case .xray: return "中性白色透视轮廓与逐层料道。保留完整打印几何；分析模式仍用彩色显示数值。"
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
        let key = mode == .flow ? "flow" : mode == .height ? "layer_height" : showTravel ? "all_speed" : "print_speed"
        return ranges[key] ?? [0, 0]
    }
}

struct LayerHeightLegend: View {
    let data: PreviewResult
    @State private var scale = LayerHeightColors(heights: [])
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                uiText("层高 · mm").interfaceFont(.caption, weight: .bold)
                Spacer()
                uiText("按打印层高分色").interfaceFont(.caption).foregroundColor(.secondary)
            }
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading, spacing: 6
                ) {
                    ForEach(scale.entries) { entry in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: entry.rgb[0], green: entry.rgb[1], blue: entry.rgb[2]))
                                .frame(width: 20, height: 12)
                            uiText(entry.label + " mm").interfaceFont(.caption).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                }.padding(.trailing, 10)
            }.frame(height: scale.entries.count > 6 ? 64 : 24)
            if scale.entries.count > 6 {
                uiText("可滚动查看全部打印层高。").interfaceFont(.caption2).foregroundColor(.secondary)
            }
        }
        .task(id: data.sha256) {
            let heights = data.layer_heights ?? []
            let next = await Task.detached(priority: .userInitiated) { LayerHeightColors(heights: heights) }.value
            guard !Task.isCancelled else { return }
            scale = next
        }
    }
}

struct MetricLegend: View {

    let mode: PreviewMode
    let limits: [Double]
    private var uniform: Bool { abs(limits[1] - limits[0]) < 0.0000001 }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                uiText("\(L(mode.rawValue)) · \(mode.unit)").interfaceFont(.caption, weight: .bold)
                Spacer()
                uiText(uniform ? "数值一致" : "色标固定为整件路径范围").interfaceFont(.caption).foregroundColor(.secondary)
            }
            if uniform {
                RoundedRectangle(cornerRadius: 3).fill(metricColor(0.5)).frame(height: 8)
                uiText(mode.label(limits[0]) + " " + mode.unit).interfaceFont(.caption).monospacedDigit()
            } else {
                RoundedRectangle(cornerRadius: 3).fill(
                    LinearGradient(
                        colors: (0...16).map { metricColor(Double($0) / 16) }, startPoint: .leading, endPoint: .trailing
                    )
                ).frame(height: 8)
                HStack {
                    uiText(mode.label(limits[0]))
                    Spacer()
                    uiText(mode.label((limits[0] + limits[1]) / 2))
                    Spacer()
                    uiText(mode.label(limits[1]))
                }.interfaceFont(.caption).monospacedDigit()
            }
        }
    }
}
