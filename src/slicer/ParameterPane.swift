import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ParameterPane: View {

    @ObservedObject var model: Workbench
    @State private var effectsExpanded = false
    func row(_ label: String, _ key: String, _ unit: String = "mm") -> some View {
        NumberRow(model: model, label: label, key: key, unit: unit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PrinterSelector(model: model)
            NeutralSegments(titles: ["造型", "底部", "补偿", "打印"], values: [0, 4, 2, 3], selection: $model.parameterTab)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.parameterTab == 0 {
                            ShapeControls(model: model)
                            if model.supportsEffects || model.hasActiveEffects {
                                Divider()
                                DisclosureGroup(L("表面效果"), isExpanded: $effectsExpanded) { WaveControls(model: model) }
                                    .onAppear { if model.hasActiveEffects { effectsExpanded = true } }
                            }
                        } else if model.parameterTab == 4 {
                            BottomControls(model: model)
                        } else if model.parameterTab == 2 {
                            CompensationControls(model: model).id("compensation")
                        } else if model.isBambu {
                            PrintQualityControls(model: model)
                            BambuControls(model: model)
                        } else {
                            PrintQualityControls(model: model)
                            PelletMaterialControls(model: model)
                            Divider()
                            uiText("温度").interfaceFont(.headline)
                            row("喷嘴温度", "NT", "°C")
                            row("热床温度", "BT", "°C")
                            row("热区 1", "ZONE1", "°C")
                            row("热区 2", "ZONE2", "°C")
                            row("热区 3", "ZONE3", "°C")
                            Divider()
                            uiText("流量与速度").interfaceFont(.headline)
                            row("流量比例", "FM", "×")
                            if model.fields["SourceMode"] == "TravelTest" {
                                uiText("跨孔测试固定打印速度：9 mm/s（含裙边、首层和主体）。").interfaceFont(.caption).foregroundColor(
                                    .secondary)
                            } else {
                                speedRow("底部填充速度", "BottomF")
                                speedRow("外墙速度", "WallF")
                            }
                            Divider()
                            uiText("位置与收尾").interfaceFont(.headline)
                            Toggle(L("左侧对齐裙边、首层与收尾"), isOn: model.toggle("AlignLeft"))
                            ContextHelp(
                                model.fields["SourceMode"] == "DoubleScroll" && model.fields["DoubleLines"] == "3"
                                    ? "花瓶模式的首层起点、连续上升起点与顶部收尾固定在轮廓最左侧。"
                                    : model.fields["SourceMode"] == "DoubleScroll"
                                        ? "双螺旋开启后，单线收尾位于左侧端点，双线接缝与收尾位于轮廓最左侧。"
                                        : "最后不足一圈会走完整圈并减小上升量，总高度不变，挤出按实际间隙计算。三角波末遍回到接缝；关闭后沿用原起点与末尾相位。")
                            Divider()
                            uiText("1000 × 1000 mm 平台").interfaceFont(.subheadline)
                            row("模型中心 X", "CX")
                            row("模型中心 Y", "CY")
                            if [
                                "SingleBud", "CornerPipe", "EggScroll", "Wardrobe", "TravelTest", "Fern1060",
                                "Fern1060E", "PipeScroll", "PelletBottle",
                            ].contains(model.fields["SourceMode"] ?? "")
                                || (model.fields["SourceMode"] == "DoubleScroll" && model.fields["DoubleLines"] == "3")
                            {
                                uiText("花瓶顶部自动整平").interfaceFont(.subheadline)
                                ContextHelp("按最后一周留下的实际间隙补齐顶部，再回抽抬 Z；不叠加末段减流。其他走线方式的收尾参数仍保留。")
                            } else {
                                Toggle(L("顶部减流收尾"), isOn: model.toggle("Finish"))
                                if model.toggle("Finish").wrappedValue {
                                    row("收尾流量比例", "FinishFlow", "×")
                                    if model.fields["SourceMode"] == "NonplanarCylinder" {
                                        uiText("沿完整起伏口沿逐渐减流，不叠加末段二次减流。").interfaceFont(.caption).foregroundColor(
                                            .secondary)
                                    }
                                    if model.toggle("WaveEnabled").wrappedValue
                                        || model.toggle("MeshEnabled").wrappedValue
                                        || ["DoubleScroll", "Crescent"].contains(model.fields["SourceMode"] ?? "")
                                    {
                                        row("末段收尾长度", "FinishLength")
                                        uiText("沿最后一段路径逐渐减流，保持造型轮廓。").interfaceFont(.caption).foregroundColor(
                                            .secondary)
                                    }
                                }
                            }
                            DisclosureGroup(L("回抽与颗粒挤出")) {
                                VStack(spacing: 12) {
                                    row("回抽长度", "G1_RETRACT", "E")
                                    row("额外恢复挤出量", "G1_RESTART_EXTRA", "E")
                                    row("回抽时抬升 Z", "G1_Z_HOP")
                                    speedRow("空移速度", "G1_TRAVEL_F")
                                    speedRow("回抽速度", "G1_RETRACT_F")
                                    speedRow("回抽恢复速度", "G1_RESTORE_F")
                                    Toggle(L("回抽时擦拭"), isOn: model.toggle("G1_WIPE"))
                                    row("擦拭前回抽比例", "G1_RETRACT_BEFORE_WIPE", "%")
                                        .disabled(!model.toggle("G1_WIPE").wrappedValue)
                                    uiText("0–100%；只调整回抽时机，总回抽量不变。也用于其他空移和打印收尾。").interfaceFont(.caption)
                                        .foregroundColor(.secondary)
                                    row("擦拭距离", "G1_WIPE_DISTANCE")
                                    ContextHelp("自动裙边启用擦拭时，首尾预留约 2 mm 净空，沿末段倒退擦拭后抬升，避开起点接头；实际料头需试打确认。")
                                    row("挤出机每转体积", "ROTATION_VOLUME", "mm³")
                                    row("颗粒挤出倍率", "PF", "×")

                                }.padding(.top, 10)
                            }
                        }
                    }.padding(.vertical, 4)
                }

            }
        }.padding(16).frame(maxWidth: .infinity).disabled(model.busy)
    }
    func speedRow(_ label: String, _ key: String) -> some View {
        NumberRow(model: model, label: label, key: key, unit: "mm/s")
    }

}
