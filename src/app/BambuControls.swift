import AppKit
import SwiftUI

extension Workbench {
    var printerModel: String { fields["PrinterModel"] ?? "G1" }
    var isBambu: Bool { printerModel != "G1" }
    var printerSelection: Binding<String> { Binding(get: { self.printerModel }, set: { self.selectPrinter($0) }) }
    var nozzleSelection: Binding<String> {
        Binding(
            get: { self.fields["Nozzle"] ?? "0.4" },
            set: { value in
                self.fields["Nozzle"] = value
                let n = Double(value) ?? 0.4
                for (k, v) in [
                    "W": n * 1.125, "WB": n * 1.125, "H": n / 2, "BH": n / 2, "H0": n / 2, "InnerStartW": n,
                    "TriplePitch": n / 2,
                ] { self.fields[k] = String(format: "%.4g", v) }
                self.prepareMaterialLibrary()
                self.dirty = true
            })
    }
    func selectPrinter(_ next: String) {
        guard next != printerModel, !busy else { return }
        finishPlacement()
        rememberShape()
        let store = preferences
        store.set(fields, forKey: "149.machine.fields." + printerModel)
        if let cached = store.dictionary(forKey: "149.machine.fields." + next) as? [String: String] {
            fields.merge(cached, uniquingKeysWith: { $1 })
        } else if next != "G1" {
            // A fresh machine gets a small lamp and filament settings. Returning
            // to another machine restores its entire draft, including its EF.
            let center = next == "H2D" ? (162.5, 160.0) : next == "A1 mini" ? (90.0, 90.0) : (128.0, 128.0)
            let preset: [String: String] = [
                "SourceMode": "Cylinder", "Dout": "60", "Din": "20", "CH": "40", "ConeBottomD": "60", "ConeTopD": "40",
                "ConeHeight": "40", "TripleD": "60", "TripleHeight": "10", "TriplePitch": "0.2", "N": "0",
                "Tolerance": "0.02", "W": "0.45", "WB": "0.45", "H": "0.2", "BH": "0.2", "H0": "0.2", "Nozzle": "0.4",
                "H2DNozzle": "Left", "B": "1", "HasBottom": "0", "EF": "0.15", "EFLayers": "3",
                "EFTable": "0:100\n1:65\n2:25\n3:0", "EFEnabled": "0", "InnerStartW": "0.4", "WaveEnabled": "0",
                "WaveAmp": "0.5", "WaveNegAmp": "0", "FilamentType": "PETG", "FilamentDiameter": "1.75",
                "MaxVolumetric": "8", "BBRetraction": "0.8", "BBRetractionSpeed": "30", "BBTravel": "100",
                "BBHop": "0.4", "BBFan": "40", "NT": "245", "BT": "70", "FM": "1", "F0": "1", "PF": "1",
                "BottomF": "20", "WallF": "30", "SKIRT_F": "20", "SKIRT_GAP": "3", "FinishLength": "5", "Finish": "1",
                "BuildPlate": "Textured PEI Plate", "Density": "1.27", "ExtraWasteG": "0", "CX": String(center.0),
                "CY": String(center.1),
            ]
            fields.merge(preset, uniquingKeysWith: { $1 })
        }
        fields.removeValue(forKey: "ImportFile")
        fields.removeValue(forKey: "ImportScale")
        if fields["SourceMode"] == "Imported" { fields["SourceMode"] = "Cylinder" }
        fields["PrinterModel"] = next
        let placement = preferences.dictionary(forKey: "149.placement.transform." + next) as? [String: Double]
        restorePlacement(placement ?? ["rotation": preferences.double(forKey: "149.placement.rotation." + next)])
        prepareMaterialLibrary()
        loadMaterialAppearance()
        store.set(fields, forKey: "149.machine.fields." + next)
        store.set(next, forKey: "149.lastPrinter")
        preview = nil
        dirty = true
        savedURL = nil
        status = "已切换机型，请核对材料和喷嘴后切片。"
    }
    func openBambuConnect() {
        if let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "bambu-connect://import-file")!) {
            NSWorkspace.shared.open(app)
        } else {
            self.error = L("尚未安装 Bambu Connect。请在打印设置中打开官方安装页面。")
        }
    }
    func sendToBambu() {
        guard isBambu, !dirty, !busy, let raw = gcodeURL else { return }
        let source = URL(fileURLWithPath: raw.path + ".3mf")
        var link = URLComponents()
        link.scheme = "bambu-connect"
        link.host = "import-file"
        do {
            // Stable local copy survives a new preview, project switch or quit.
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("149/Transfers")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name =
                "149_" + printerModel.replacingOccurrences(of: " ", with: "_") + "_" + UUID().uuidString.prefix(8)
                + ".gcode.3mf"
            let target = dir.appendingPathComponent(name)
            try Data(contentsOf: source).write(to: target, options: .atomic)
            link.queryItems = [
                URLQueryItem(name: "path", value: target.path), URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "version", value: "1.1.0"),
            ]
            guard let url = link.url else { throw message("无法构建 Bambu Connect 链接。") }
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                NSWorkspace.shared.activateFileViewerSelecting([target])
                throw message("尚未安装 Bambu Connect。文件已准备好，可先安装官方软件，再点击发送。")
            }
            guard NSWorkspace.shared.open(url) else { throw message("Bambu Connect 未能打开，请检查安装。") }
            savedURL = target
            status = "已交给 Bambu Connect，请在官方窗口确认打印机和耗材。"
        } catch { self.error = error.localizedDescription }
    }
}

struct PrinterSelector: View {
    @ObservedObject var model: Workbench
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FabricationIcon()
                uiText("打印机").font(.headline)
                Spacer()
                Button {
                    editing = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless).help(L("编辑打印机")).accessibilityLabel(L("编辑打印机"))
            }
            ParameterPicker(
                L("打印机"), selection: model.printerSelection,
                options: [.init("Ginger G1", "G1")]
                    + ["H2D", "P1P", "A1", "A1 mini"].map { .init("Bambu Lab " + $0, $0) }
            ).labelsHidden()
        }.sheet(isPresented: $editing) { PrinterEditor(model: model) }
    }
}

struct BambuControls: View {
    @ObservedObject var model: Workbench

    func row(_ label: String, _ key: String, _ unit: String = "mm") -> some View {
        NumberRow(model: model, label: label, key: key, unit: unit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Link(
                L("安装 Bambu Connect"), destination: URL(string: "https://wiki.bambulab.com/en/software/bambu-connect")!
            ).foregroundColor(.primary)
            ContextHelp("首次使用请先在 Bambu Connect 登录并连接机器。发送后在官方窗口确认打印，不重新切片。")
            if model.printerModel == "H2D" {
                DisclosureGroup(L("启动流程")) {
                    ParameterPicker(
                        L("启动方式"), selection: model.binding("H2DStartup"),
                        options: [.init("官方完整启动", "Official"), .init("简化启动（已装料）", "Simple")])
                    if model.fields["H2DStartup"] == "Simple" {
                        uiText("先装好所选喷嘴的耗材。归零、抬升并等待温度后开始；不额外冲刷、动态流量校准或重新调平。").interfaceFont(.caption).foregroundColor(
                            .secondary)
                        uiText("喷嘴选择仍由机器执行；未装好料时可能触发换料。结束仍使用官方退料流程。").interfaceFont(.caption).foregroundColor(
                            .secondary)
                    }
                    Divider()
                }
            }
        }
    }
}

struct FilamentFlowAssessment: View {
    @ObservedObject var model: Workbench

    struct Entry: Identifiable {
        let id: String
        let width: Double
        let height: Double
        let speed: Double
        let factor: Double
        var area: Double { height * (width - height * (1 - Double.pi / 4)) * factor }
        var demand: Double { area * speed }
    }
    func n(_ key: String) -> Double { Double(model.fields[key] ?? "") ?? .nan }
    var entries: [Entry] {
        let bottom =
            model.toggle("HasBottom").wrappedValue
            && !["Triple", "DoubleScroll", "SingleBud", "CornerPipe", "EggScroll", "Wardrobe"].contains(
                model.fields["SourceMode"] ?? "")
        let w = bottom ? n("WB") : n("W")
        var rows = [
            Entry(
                id: "首层", width: w, height: n("H0"), speed: n(bottom ? "BottomF" : "WallF"), factor: n("FM") * n("F0")),
            Entry(
                id: "外墙", width: n("W"), height: n(model.fields["SourceMode"] == "Triple" ? "TriplePitch" : "H"),
                speed: n("WallF"), factor: n("FM")),
            Entry(id: "裙边", width: w, height: n("H0"), speed: n("SKIRT_F"), factor: n("FM") * n("F0")),
        ]
        if !model.toggle("SKIRT_AUTO").wrappedValue { rows.removeLast() }
        if bottom && n("B") > 1 {
            rows.append(Entry(id: "底部", width: n("WB"), height: n("BH"), speed: n("BottomF"), factor: n("FM")))
        }
        return rows
    }
    var valid: Bool {
        n("MaxVolumetric").isFinite && n("MaxVolumetric") > 0
            && entries.allSatisfy {
                $0.width.isFinite && $0.height.isFinite && $0.speed.isFinite && $0.factor.isFinite && $0.height > 0
                    && $0.width >= $0.height && $0.speed > 0 && $0.factor > 0
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            uiText("流量评估 · MVS").interfaceFont(.subheadline, weight: .semibold)
            if valid {
                HStack {
                    uiText("路径")
                    Spacer()
                    uiText("需求 mm³/s")
                    uiText("限流后 mm/s").frame(width: 105, alignment: .trailing)
                }.interfaceFont(.caption).foregroundColor(.secondary)
                ForEach(entries) { entry in
                    HStack {
                        uiText(entry.id)
                        Spacer()
                        uiText(String(format: "%.2f", entry.demand)).monospacedDigit().foregroundColor(
                            entry.demand > n("MaxVolumetric") ? .orange : .primary)
                        uiText(String(format: "%.2f", min(entry.speed, n("MaxVolumetric") / entry.area)))
                            .monospacedDigit().frame(width: 105, alignment: .trailing)
                    }.interfaceFont(.callout)
                }
                ContextHelp("需求按设定速度估算；超过 MVS 时自动降速，保留挤出体积。MVS 是你设定的材料与热端上限，不是软件测出的机器能力。")
                if let flow = model.preview?.flow_report, !model.dirty {
                    Divider()
                    uiText(String(format: L("路径峰值：需求 %.2f → 输出 %.2f mm³/s"), flow.requested_peak, flow.effective_peak))
                        .interfaceFont(.caption).monospacedDigit()
                    uiText(String(format: L("限流线段：%d"), flow.limited_segments)).interfaceFont(.caption)
                }
                if n("Nozzle") > 0 {
                    let height = entries.map(\.height).max() ?? 0
                    let width = entries.map(\.width).max() ?? 0
                    uiText(
                        String(format: L("层高 / 孔径 %.2f× · 线宽 / 孔径 %.2f×"), height / n("Nozzle"), width / n("Nozzle"))
                    ).interfaceFont(.caption).monospacedDigit()
                    if height / n("Nozzle") > 0.8 || width / n("Nozzle") > 2 {
                        uiText("实验挤出：较高层高或较宽料道可能贴合不足、拖拽或尺寸不稳。降速只降低流量需求，不能保证成形；估算截面也不等于实测料道。").interfaceFont(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                uiText("输入有效的线宽、层高、速度和流量比例后显示估算。").interfaceFont(.caption).foregroundColor(.secondary)
            }
        }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Workbench {
    var printerBedSize: [Double] {
        switch printerModel {
        case "H2D": return [350, 320, 325]
        case "P1P", "A1": return [256, 256, 256]
        case "A1 mini": return [180, 180, 180]
        default: return [1000, 1000, 1000]
        }
    }
}
