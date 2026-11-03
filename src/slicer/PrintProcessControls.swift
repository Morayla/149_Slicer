import SwiftUI

struct PrintProcessControls: View {
    @ObservedObject var model: Workbench
    private func row(_ title: String, _ key: String, _ unit: String = "mm") -> some View {
        NumberRow(model: model, label: title, key: key, unit: unit)
    }
    private var automaticFinish: Bool {
        [
            "SingleBud", "CornerPipe", "EggScroll", "Wardrobe", "TravelTest", "Fern1060", "Fern1060E", "PipeScroll",
            "PelletBottle",
        ]
        .contains(model.fields["SourceMode"] ?? "")
            || (model.fields["SourceMode"] == "DoubleScroll" && model.fields["DoubleLines"] == "3")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PrintQualityControls(model: model)
            uiText("打印速度").font(.headline)
            if model.fields["SourceMode"] == "TravelTest" {
                StaticNumberRow(label: "打印速度", value: "9", unit: "mm/s")
            } else {
                row("底部填充", "BottomF", "mm/s")
                row("外墙", "WallF", "mm/s")
            }
            if model.isBambu { FilamentFlowAssessment(model: model) }
            Divider()
            FirstLayerControls(model: model)
            Divider()
            CompensationControls(model: model)
            Divider()
            uiText("空移与擦拭").font(.headline)
            row("空移速度", model.isBambu ? "BBTravel" : "G1_TRAVEL_F", "mm/s")
            row("回抽抬升", model.isBambu ? "BBHop" : "G1_Z_HOP")
            if !model.isBambu {
                Toggle(L("回抽时擦拭"), isOn: model.toggle("G1_WIPE"))
                if model.toggle("G1_WIPE").wrappedValue {
                    row("擦拭距离", "G1_WIPE_DISTANCE")
                    row("擦拭前回抽", "G1_RETRACT_BEFORE_WIPE", "%")
                }
            }
            Divider()
            uiText("接缝与收尾").font(.headline)
            Toggle(L("接缝对齐左侧"), isOn: model.toggle("AlignLeft"))
            if automaticFinish {
                uiText("顶部自动整平").font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle(L("顶部减流收尾"), isOn: model.toggle("Finish"))
                if model.toggle("Finish").wrappedValue {
                    row("收尾流量比例", "FinishFlow", "×")
                    if model.toggle("WaveEnabled").wrappedValue || model.toggle("MeshEnabled").wrappedValue
                        || ["DoubleScroll", "Crescent"].contains(model.fields["SourceMode"] ?? "")
                    {
                        row("末段收尾长度", "FinishLength")
                    }
                }
            }
            row("额外耗料", "ExtraWasteG", "g")
        }
    }
}

struct PrinterEditor: View {
    @ObservedObject var model: Workbench
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            uiText(model.isBambu ? "Bambu Lab " + model.printerModel : "Ginger G1").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    uiText("打印平台").font(.headline)
                    ForEach(Array(zip(["宽度", "深度", "高度"], model.printerBedSize)), id: \.0) { title, value in
                        StaticNumberRow(label: title, value: NumericField.format(value))
                    }
                    Divider()
                    if model.isBambu {
                        ParameterPicker(
                            L("喷嘴直径"), selection: model.nozzleSelection,
                            options: ["0.4", "0.6", "0.8"].map { .init($0 + " mm", $0) })
                        if model.printerModel == "H2D" {
                            ParameterPicker(
                                L("打印喷嘴"), selection: model.binding("H2DNozzle"),
                                options: [.init("左喷嘴", "Left"), .init("右喷嘴", "Right")])
                        }
                        ParameterPicker(
                            L("打印板"), selection: model.binding("BuildPlate"),
                            options: [.init("纹理 PEI 板", "Textured PEI Plate"), .init("光面高温板", "High Temp Plate")])
                        BambuControls(model: model)
                    } else {
                        uiText("挤出机标定").font(.headline)
                        NumberRow(model: model, label: "每转挤出体积", key: "ROTATION_VOLUME", unit: "mm³")
                    }
                }.padding(.trailing, 4)
            }
            HStack {
                Spacer()
                Button(L("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 430, height: model.isBambu ? 470 : 280)
    }
}
