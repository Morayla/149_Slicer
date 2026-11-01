import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class Workbench: ObservableObject {
    @Published var parameterTab = 0
    @Published var selectedEFPresetID = ""
    @Published var selectedNoisePresetID = ""
    @Published var showSendSheet = false
    @Published var documentURL: URL?
    private var shapeDrafts: [String: [String: String]] = [:]
    private var draftTask: DispatchWorkItem?
    var canSlice: Bool { !busy && !modelRefreshing && !modelNeedsUpdate && modelError == nil }
    var canSend: Bool { !busy && !dirty && preview != nil }
    var canImport: Bool { !busy }
    var sendTitle: String { isBambu ? "发送到 Bambu Connect…" : "发送…" }
    func requestSend() {
        guard canSend else { return }
        if isBambu { sendToBambu() } else { showSendSheet = true }
    }
    func persistDraft() {
        draftTask?.cancel()
        let draft = fields
        let store = preferences
        let printer = printerModel
        let task = DispatchWorkItem {
            store.set(draft, forKey: "149.machine.fields." + printer)
            store.set(printer, forKey: "149.lastPrinter")
        }
        draftTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }
    func flushDraft() {
        draftTask?.cancel()
        preferences.set(fields, forKey: "149.machine.fields." + printerModel)
        preferences.set(printerModel, forKey: "149.lastPrinter")
    }
    func rememberShape() {
        let keys = Set((defaults["shape"] as? [String: Any] ?? [:]).keys).union(
            (defaults["process"] as? [String: Any] ?? [:]).keys)
        shapeDrafts[printerModel + ":" + (fields["SourceMode"] ?? "")] = fields.filter { keys.contains($0.key) }
    }
    @Published var fields: [String: String] = [:]
    @Published var preview: PreviewResult?
    @Published var modelGeometry: ModelGeometry?
    @Published var showingModel = true
    @Published var previewMode: PreviewMode = .role
    @Published var showTravel = false
    @Published var showBed = false
    @Published var showBeads = true
    @Published var panMode = false
    @Published var beadViewAction = 0
    @Published var previewZoom = 1.0
    func cameraAction(_ mode: Int) {
        if [0, 2, 6].contains(mode) { previewZoom = 1 }
        if mode == 0 { panMode = false }
        if mode == 6 { showBed = true }
        beadViewAction = ((beadViewAction / 10) + 1) * 10 + mode
    }
    @Published var operation = ""
    private var preparedModel: NativePreparedModel?
    private var preparedFields: [String: String] = [:]
    var modelNeedsUpdate: Bool { preparedModel == nil || preparedFields != modelInputs }
    private var modelInputs: [String: String] {
        var keys = Set((defaults["shape"] as? [String: Any] ?? [:]).keys)
        keys.formUnion((defaults["process"] as? [String: Any] ?? [:]).keys)
        keys.insert("PrinterModel")
        if ["1", "true", "1.0"].contains(fields["EdgeCalibrationEnabled"] ?? "") {
            keys.formUnion(["PF", "FM", "F0"])
        }
        return fields.filter { keys.contains($0.key) }
    }
    @Published var modelRefreshing = false
    @Published var modelError: String?
    private var modelRevision = 0
    private var modelTask: DispatchWorkItem?
    private var modelComputation: SliceComputation?
    private var modelRunning = false
    private let modelQueue = DispatchQueue(label: "149.model-preview", qos: .userInitiated)
    private var modelCache: [(inputs: [String: String], prepared: NativePreparedModel, geometry: ModelGeometry)] = []
    func scheduleModelPreview(immediate: Bool = false) {
        guard !busy else { return }
        modelRevision += 1
        modelTask?.cancel()
        modelComputation?.cancel()
        modelError = nil
        guard modelNeedsUpdate else {
            modelRefreshing = false
            return
        }
        showingModel = true
        dirty = true
        modelRefreshing = true
        let inputs = modelInputs
        if fields["SourceMode"] != "Imported", let cached = modelCache.first(where: { $0.inputs == inputs }) {
            preparedModel = cached.prepared
            preparedFields = inputs
            modelGeometry = cached.geometry
            modelRefreshing = false
            return
        }
        guard !modelRunning else { return }
        let work = DispatchWorkItem { [weak self] in self?.generateModel() }
        modelTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.3), execute: work)
    }
    func generateModel() {
        guard !busy, !modelRunning, modelNeedsUpdate else {
            modelRefreshing = false
            return
        }
        let revision = modelRevision
        let inputs = modelInputs
        do {
            guard let engine = engine else { throw message("原生切片引擎未能初始化。") }
            let raw = try project()
            let computation = SliceComputation()
            modelComputation = computation
            modelRunning = true
            modelRefreshing = true
            modelError = nil
            modelQueue.async { [weak self] in
                do {
                    let (prepared, geometry) = try computation.run {
                        let prepared = try engine.prepareModel(raw)
                        return (prepared, try ModelGeometry(prepared))
                    }
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.modelRunning = false
                        guard revision == self.modelRevision, inputs == self.modelInputs else {
                            self.scheduleModelPreview(immediate: true)
                            return
                        }
                        self.preparedModel = prepared
                        self.preparedFields = inputs
                        self.modelGeometry = geometry
                        self.modelRefreshing = false
                        self.modelError = nil
                        if self.fields["SourceMode"] != "Imported", prepared.shape.wall.count < 50000 {
                            self.modelCache.removeAll { $0.inputs == inputs }
                            self.modelCache.append((inputs, prepared, geometry))
                            if self.modelCache.count > 2 { self.modelCache.removeFirst() }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.modelRunning = false
                        guard revision == self.modelRevision else {
                            self.scheduleModelPreview(immediate: true)
                            return
                        }
                        self.modelRefreshing = false
                        self.modelError = error.localizedDescription
                    }
                }
            }
        } catch {
            modelRefreshing = false
            modelError = error.localizedDescription
        }
    }
    @Published var busy = false
    @Published var dirty = true
    @Published var status = "选择造型并设置尺寸。"
    @Published var error: String?
    @Published var savedURL: URL?
    @Published var zLimit = 150.0
    private let speedKeys: Set<String> = [
        "F", "BottomF", "WallF", "SKIRT_F", "G1_TRAVEL_F", "G1_Z_F", "G1_RETRACT_F", "G1_RESTORE_F", "G1_WIPE_F",
    ]
    private var defaults: [String: Any] = [:]
    var gcodeURL: URL?
    private var tempFolder: URL?
    private var sliceCache: [Data: URL] = [:]
    private var sliceCacheOrder: [Data] = []
    private let resource: URL
    let preferences: UserDefaults
    private var engine: NativeSliceEngine?

    init(resource: URL = Bundle.main.resourceURL!, preferences: UserDefaults = .standard) {
        self.resource = resource
        self.preferences = preferences
        do {
            let data = try Data(contentsOf: resource.appendingPathComponent("definitions/defaults.json"))
            defaults = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            engine = try NativeSliceEngine(resources: resource)
            try applyProject(defaults)
            if let name = preferences.string(forKey: "149.lastPrinter"),
                let draft = preferences.dictionary(forKey: "149.machine.fields." + name) as? [String: String]
            {
                fields.merge(draft, uniquingKeysWith: { $1 })
            }
        } catch { self.error = LF("无法读取内置参数：%@", String(error.localizedDescription)) }
    }
    deinit {
        for folder in Set(sliceCache.values) { try? FileManager.default.removeItem(at: folder) }
        if let folder = tempFolder { try? FileManager.default.removeItem(at: folder) }
    }
    func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { self.fields[key] ?? "" },
            set: { value in
                if key == "SourceMode" {
                    guard value != self.fields[key] else { return }
                    self.rememberShape()
                    if let draft = self.shapeDrafts[self.printerModel + ":" + value] {
                        self.fields.merge(draft, uniquingKeysWith: { $1 })
                        self.fields[key] = value
                        self.dirty = true
                        return
                    }
                }
                let wasFern = ["Fern1060", "Fern1060E"].contains(self.fields["SourceMode"] ?? "")
                self.fields[key] = value
                if key == "SourceMode" && value == "EggScroll" {
                    self.fields.merge(["W": "6", "H": "3", "H0": "2.5"], uniquingKeysWith: { _, new in new })
                }
                if key == "SourceMode" && value == "Wardrobe" {
                    for field in ["H", "H0"] {
                        if let height = Double(self.fields[field] ?? ""), height > 3.5 { self.fields[field] = "3.5" }
                    }
                }
                if key == "SourceMode" && value == "Hopper" {
                    self.fields.merge(
                        [
                            "W": "8", "WB": "8", "H": "3.5", "H0": "3.5", "BH": "3.5", "HasBottom": "0", "N": "288",
                            "AlignLeft": "1", "EdgeCalibrationEnabled": "0", "WaveEnabled": "0", "MeshEnabled": "0",
                            "NoiseEnabled": "0", "NoiseZEnabled": "0",
                        ], uniquingKeysWith: { $1 })
                }
                if key == "SourceMode" && value == "PelletBottle" {
                    self.fields.merge(
                        [
                            "W": "8", "WB": "8", "H": "3.5", "H0": "3.5", "BH": "3.5", "B": "2", "HasBottom": "1",
                            "BottomKind": "Solid", "BottomPattern": "Zigzag", "EFEnabled": "0", "AlignLeft": "1",
                            "EdgeCalibrationEnabled": "0", "WaveEnabled": "0", "MeshEnabled": "0", "NoiseEnabled": "0",
                            "NoiseZEnabled": "0",
                        ], uniquingKeysWith: { $1 })
                }
                if key == "SourceMode" && value == "PipeScroll" {
                    self.fields.merge(
                        [
                            "PipeScrollProfile": "2", "PipeScrollSpacing": "167.96", "PipeScrollRot": "0",
                            "PipeScrollHeight": "250", "W": "8", "H": "3", "H0": "2.5", "HasBottom": "0",
                            "EFEnabled": "0", "WaveEnabled": "0", "MeshEnabled": "0", "NoiseEnabled": "0",
                            "NoiseZEnabled": "0",
                        ], uniquingKeysWith: { $1 })
                }
                if key == "PipeScrollProfile" {
                    let profileDefaults: [String: String] =
                        value == "2"
                        ? ["W": "8", "PipeScrollSpacing": "167.96", "PipeScrollRot": "0", "PipeScrollHeight": "250"]
                        : (value == "1"
                            ? ["W": "6", "PipeScrollSpacing": "215", "PipeScrollRot": "-6.4"]
                            : ["W": "6", "PipeScrollSpacing": "150", "PipeScrollRot": "0"])
                    self.fields.merge(profileDefaults, uniquingKeysWith: { $1 })
                }
                if key == "SourceMode" && ["Fern1060", "Fern1060E"].contains(value) && !wasFern {
                    self.fields.merge(
                        [
                            "W": "8", "H": "3.5", "H0": "3.5", "HasBottom": "0", "EFEnabled": "0", "WaveEnabled": "0",
                            "MeshEnabled": "0", "NoiseEnabled": "0", "NoiseZEnabled": "0",
                        ], uniquingKeysWith: { $1 })
                }
                self.dirty = true
            })
    }
    func toggle(_ key: String) -> Binding<Bool> {
        Binding(
            get: { ["1", "true", "1.0"].contains(self.fields[key] ?? "") },
            set: {
                self.fields[key] = $0 ? "1" : "0"
                self.dirty = true
            })
    }
    func project() throws -> [String: Any] {
        var output: [String: Any] = ["version": 1]
        for group in ["shape", "machine", "process", "material"] {
            let schema = defaults[group] as! [String: Any]
            var values: [String: Any] = [:]
            for (key, value) in schema {
                let raw = fields[key] ?? ""
                if value is String {
                    values[key] = raw
                } else if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
                    values[key] = ["1", "true", "1.0"].contains(raw)
                } else {
                    guard let number = Double(raw), number.isFinite else {
                        throw message(LF("%@ 请输入有效数字。", String(key)))
                    }
                    values[key] = speedKeys.contains(key) ? number * 60 : number
                }
            }
            output[group] = values
        }
        return output
    }
    func message(_ s: String) -> NSError {
        NSError(domain: "149.Slicer", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }
    func applyProject(_ raw: [String: Any]) throws {
        guard raw["version"] as? Int == 1 else { throw message("不支持的项目版本。") }
        var next: [String: String] = [:]
        for group in ["shape", "machine", "process", "material"] {
            let values: [String: Any]
            if ["process", "material"].contains(group) && raw[group] == nil {
                values = [:]
            } else if let existing = raw[group] as? [String: Any] {
                values = existing
            } else {
                throw message(LF("项目缺少 %@ 参数。", String(group)))
            }
            let schema = defaults[group] as! [String: Any]
            if let unknown = values.keys.first(where: { schema[$0] == nil }) {
                throw message(LF("本版不支持参数 %@。", String(unknown)))
            }
            for (key, fallback) in schema {
                let value = values[key] ?? fallback
                if let s = value as? String {
                    next[key] = s
                } else if let number = value as? NSNumber {
                    if speedKeys.contains(key) {
                        next[key] = String(format: "%.9g", number.doubleValue / 60)
                    } else if key.hasPrefix("WardEFLayer") || key.hasPrefix("WardPostEFLayer") {
                        next[key] = String(format: "%.12g", number.doubleValue)
                    } else {
                        next[key] = number.stringValue
                    }
                } else {
                    throw message(LF("%@ 参数格式无效。", String(key)))
                }
            }
        }
        guard
            [
                "Cylinder", "Ellipse", "Cone", "Triple", "TripleVase", "DoubleScroll", "NonplanarCylinder", "Imported",
                "Crescent", "SingleBud", "CornerPipe", "EggScroll", "Wardrobe", "TravelTest", "Fern1060", "Fern1060E",
                "PipeScroll", "PelletBottle", "Hopper",
            ].contains(next["SourceMode"] ?? "")
        else { throw message("不支持的造型类型。") }
        fields = next
        dirty = true
        savedURL = nil
        documentURL = nil
        shapeDrafts.removeAll()
        selectedEFPresetID = ""
        selectedNoisePresetID = ""
    }
    func writeProject(to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: project(), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        documentURL = url
        status = LF("项目已保存：%@", String(url.lastPathComponent))
    }
    func saveProject(asNew: Bool = false) {
        do {
            if !asNew, let url = documentURL {
                try writeProject(to: url)
                return
            }
            let panel = NSSavePanel()
            panel.title = L(asNew ? "另存项目…" : "保存项目")
            panel.nameFieldStringValue = documentURL?.lastPathComponent ?? L("149 项目.json")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try writeProject(to: url)
        } catch { self.error = error.localizedDescription }
    }
    func openProject() {
        let panel = NSOpenPanel()
        panel.title = L("打开 149 项目")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == NSApplication.ModalResponse.OK, let url = panel.url else { return }
        do {
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            guard let raw = raw else { throw message("项目格式无效。") }
            try applyProject(raw)
            documentURL = url
            preview = nil
            gcodeURL = nil
            preparedModel = nil
            modelGeometry = nil
            showingModel = true
            status = LF("已载入 %@，模型预览会自动更新。", String(url.lastPathComponent))
        } catch { self.error = error.localizedDescription }
    }
    func generate() {
        guard !busy else { return }
        guard !modelNeedsUpdate else {
            error = "模型预览正在更新，请稍候。"
            return
        }
        do {
            guard let engine = engine else { throw message("原生切片引擎未能初始化。") }
            let data = try JSONSerialization.data(withJSONObject: project(), options: [.sortedKeys])
            // Imported files can change at the same path, including while the app
            // is open. Always let the engine read and validate their current bytes.
            let cacheable = fields["SourceMode"] != "Imported"
            let cachedFolder = cacheable ? sliceCache[data] : nil
            let folder =
                cachedFolder
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("149_Slicer-" + UUID().uuidString)
            let started = Date()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if cachedFolder == nil { try data.write(to: folder.appendingPathComponent("project.json")) }
            preferences.set(fields, forKey: "149.machine.fields." + printerModel)
            preferences.set(printerModel, forKey: "149.lastPrinter")
            let prepared = preparedModel
            busy = true
            operation = "正在切片…"
            error = nil
            savedURL = nil
            status = cachedFolder == nil ? "正在生成路径与机器指令…" : "正在载入此分件的已验证切片…"
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result: PreviewResult
                    var refreshedModel: NativePreparedModel?
                    var refreshedGeometry: ModelGeometry?
                    if cachedFolder == nil {
                        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                        let generated = try engine.generate(raw, prepared: prepared)
                        try generated.write(to: folder)
                        result = try PreviewResult(native: generated)
                        if !cacheable, let prepared = prepared {
                            let fresh = NativePreparedModel(key: prepared.key, shape: generated.model)
                            refreshedGeometry = try ModelGeometry(fresh)
                            refreshedModel = fresh
                        }
                        if cacheable {
                            try JSONEncoder().encode(result).write(
                                to: folder.appendingPathComponent("result.json"), options: .atomic)
                        }
                    } else {
                        result = try JSONDecoder().decode(
                            PreviewResult.self, from: Data(contentsOf: folder.appendingPathComponent("result.json")))
                    }
                    guard result.ok else { throw self.message("生成失败。") }
                    let elapsed = Date().timeIntervalSince(started)
                    let currentModel = refreshedModel
                    let currentGeometry = refreshedGeometry
                    DispatchQueue.main.async {
                        if let currentModel = currentModel, let currentGeometry = currentGeometry {
                            self.preparedModel = currentModel
                            self.modelGeometry = currentGeometry
                        }
                        if let previous = self.tempFolder, previous != folder,
                            !self.sliceCache.values.contains(previous)
                        {
                            try? FileManager.default.removeItem(at: previous)
                        }
                        if cacheable {
                            self.sliceCache[data] = folder
                            self.sliceCacheOrder.removeAll { $0 == data }
                            self.sliceCacheOrder.append(data)
                            while self.sliceCacheOrder.count > 6 {
                                let key = self.sliceCacheOrder.removeFirst()
                                if let old = self.sliceCache.removeValue(forKey: key) {
                                    try? FileManager.default.removeItem(at: old)
                                }
                            }
                        }
                        self.tempFolder = folder
                        self.gcodeURL = folder.appendingPathComponent("preview.gcode")
                        self.preview = result
                        self.zLimit = result.height
                        self.busy = false
                        self.operation = ""
                        self.dirty = false
                        self.showingModel = false
                        if let fit = result.wave_fit {
                            self.fields["WaveCount"] = String(format: "%.9g", fit.effective)
                        }
                        if let fit = result.mesh_fit {
                            self.fields["MeshCount"] = String(format: "%.9g", fit.effective)
                        }
                        self.preparedFields = self.modelInputs
                        self.status = String(
                            format: cachedFolder == nil ? "切片及数据载入 · %.1f 秒" : "复用分件切片 · %.1f 秒", elapsed)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    DispatchQueue.main.async {
                        self.sliceCache.removeValue(forKey: data)
                        self.sliceCacheOrder.removeAll { $0 == data }
                        self.busy = false
                        self.operation = ""
                        self.dirty = true
                        self.error = error.localizedDescription
                        self.status = "生成未完成，请检查参数。"
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func exportGcode() {
        guard !dirty, !busy, let source = gcodeURL else { return }
        let panel = NSSavePanel()
        panel.title = L("导出 G-code")
        panel.nameFieldStringValue = printerModel.replacingOccurrences(of: " ", with: "_") + "_Shape.gcode"
        guard panel.runModal() == NSApplication.ModalResponse.OK, let url = panel.url else { return }
        do {
            try Data(contentsOf: source).write(to: url, options: .atomic)
            savedURL = url
            status = LF("已导出：%@", String(url.lastPathComponent))
        } catch { self.error = error.localizedDescription }
    }
}
