import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class Workbench: ObservableObject {
    @Published var parameterTab = 3
    var savedDocumentData: Data?
    @Published var selectedEFPresetID = ""
    @Published var showSendSheet = false
    @Published var documentURL: URL?
    private(set) var shapeDrafts: [String: [String: String]] = [:]
    private var draftTask: DispatchWorkItem?
    var canSlice: Bool { !busy && !modelRefreshing && !modelNeedsUpdate && modelError == nil }
    var canSend: Bool { !busy && !dirty && preview != nil }
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
        let keys = Set((defaults["shape"] as? [String: Any] ?? [:]).keys)
            .union((defaults["process"] as? [String: Any] ?? [:]).keys)
        shapeDrafts[printerModel + ":" + (fields["SourceMode"] ?? "")] = fields.filter { keys.contains($0.key) }
    }
    @Published var fields: [String: String] = [:]
    @Published var preview: PreviewResult?
    @Published var modelGeometry: ModelGeometry?
    let sharedCamera = PreviewCameraState()
    @Published var lineStrength = 0.5
    @Published var showingModel = true
    @Published var modelShading = "rendered"
    @Published var parametersVisible = true
    @Published var backgroundWhite = false {
        didSet { preferences.set(backgroundWhite, forKey: "149.preview.background.white") }
    }
    @Published var materialAppearance = MaterialAppearance() {
        didSet {
            if let data = try? JSONEncoder().encode(materialAppearance) {
                preferences.set(data, forKey: appearanceStorageKey)
            }
        }
    }
    @Published var selectedMaterialRecipeID = ""
    @Published var savedMaterialRecipes: [MaterialRecipe] = []
    @Published var factoryMaterialRecipes: [MaterialRecipe] = []
    var materialCatalog: [PelletMaterial] = []
    @Published var previewMode: PreviewMode = .role
    @Published var showTravel = false
    @Published var showBed = false
    @Published var showBeads = true
    @Published var showNozzle = true
    @Published var placementTool: PlacementTool?
    @Published var placementRotation = 0.0 {
        didSet { if placementRotation != oldValue { savePlacement() } }
    }
    @Published var placementOffset = SIMD2<Double>(repeating: 0) {
        didSet {
            if placementOffset != oldValue {
                savePlacement()
            }
        }
    }
    var placementCamera: PlacementCamera?
    var placementBedWasVisible = false
    @Published var panMode = false
    @Published var cameraOrientation = 5
    @Published var beadViewAction = 0
    @Published var previewZoom = 1.0
    func cameraAction(_ mode: Int) {
        if [1, 3, 4, 5].contains(mode) { cameraOrientation = mode }
        if mode == 0 { cameraOrientation = 5 }
        if [0, 2, 6].contains(mode) { previewZoom = 1 }
        if mode == 0 { panMode = false }
        if mode == 6 { showBed = true }
        beadViewAction = ((beadViewAction / 10) + 1) * 10 + mode
    }
    @Published var operation = ""
    private var preparedModel: NativePreparedModel?
    private var preparedFields: [String: String] = [:]
    var modelNeedsUpdate: Bool { preparedModel == nil || preparedFields != modelInputs }
    private var isAdjustingPreview = false
    func setInteractivePreview(_ adjusting: Bool) {
        guard adjusting != isAdjustingPreview else { return }
        isAdjustingPreview = adjusting
        scheduleModelPreview(immediate: true)
    }
    private var previewNeedsUpdate: Bool { modelNeedsUpdate || modelGeometry?.interactive != isAdjustingPreview }
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
    private var modelTask: DispatchWorkItem?
    private var modelRunning = false
    private var previewComputation: SliceComputation?
    private var runningInputs: [String: String] = [:]
    private let modelQueue = DispatchQueue(label: "149.model-preview", qos: .userInitiated)
    private var modelCache: [(inputs: [String: String], prepared: NativePreparedModel, geometry: ModelGeometry)] = []
    func scheduleModelPreview(immediate: Bool = false) {
        guard !busy else { return }
        modelError = nil
        guard previewNeedsUpdate else {
            modelTask?.cancel()
            modelTask = nil
            modelRefreshing = false
            return
        }
        showingModel = true
        if modelNeedsUpdate { dirty = true }
        modelRefreshing = true
        let inputs = modelInputs
        if modelRunning && inputs != runningInputs,
            !isAdjustingPreview || inputs["SourceMode"] != runningInputs["SourceMode"]
        {
            previewComputation?.cancel()
        }
        if !isAdjustingPreview,
            let cached = modelCache.first(where: { $0.inputs == inputs })
        {
            preparedModel = cached.prepared
            preparedFields = inputs
            modelGeometry = cached.geometry
            modelRefreshing = false
            return
        }
        // Finish the current frame, then pick up the latest parameters. Continuous dragging must not starve the preview.
        guard !modelRunning, modelTask == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.modelTask = nil
            self?.generateModel()
        }
        modelTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 1.0 / 30), execute: work)
    }
    func generateModel() {
        guard !busy, !modelRunning, previewNeedsUpdate else {
            modelRefreshing = false
            return
        }
        let inputs = modelInputs
        do {
            guard let engine else { throw message("原生切片引擎未能初始化。") }
            let raw = try project()
            let interactive = isAdjustingPreview
            let reusable = preparedFields == inputs && modelGeometry?.interactive == interactive ? preparedModel : nil
            let computation = SliceComputation()
            previewComputation = computation
            runningInputs = inputs
            modelRunning = true
            modelRefreshing = true
            modelError = nil
            modelQueue.async { [weak self] in
                do {
                    let (prepared, geometry) = try computation.run {
                        let prepared = try reusable ?? engine.prepareModel(raw, samplingLimit: interactive ? 128 : nil)
                        return (prepared, try ModelGeometry(prepared, interactive: interactive))
                    }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.modelRunning = false
                        if computation.isCancelled {
                            self.scheduleModelPreview(immediate: true)
                            return
                        }
                        let latest = inputs == self.modelInputs && interactive == self.isAdjustingPreview
                        if inputs == self.modelInputs
                            || (self.modelNeedsUpdate && inputs["SourceMode"] == self.modelInputs["SourceMode"])
                        {
                            self.preparedModel = prepared
                            self.preparedFields = inputs
                            self.modelGeometry = geometry
                        }
                        self.modelRefreshing = self.previewNeedsUpdate
                        if latest {
                            self.modelError = nil
                            if !interactive, prepared.shape.wall.count < 50000 {
                                self.modelCache.removeAll { $0.inputs == inputs }
                                self.modelCache.append((inputs, prepared, geometry))
                                if self.modelCache.count > 4 { self.modelCache.removeFirst() }
                            }
                        } else {
                            self.scheduleModelPreview(immediate: true)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.modelRunning = false
                        if error is CancellationError || inputs != self.modelInputs
                            || interactive != self.isAdjustingPreview
                        {
                            self.scheduleModelPreview(immediate: true)
                        } else {
                            self.modelRefreshing = false
                            self.modelError = error.localizedDescription
                        }
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
    let speedKeys: Set<String> = [
        "F", "BottomF", "WallF", "SKIRT_F", "G1_TRAVEL_F", "G1_Z_F", "G1_RETRACT_F", "G1_RESTORE_F", "G1_WIPE_F",
    ]
    private(set) var defaults: [String: Any] = [:]
    var gcodeURL: URL?
    private var tempFolder: URL?
    private struct CachedSlice {
        let folder: URL
        let preview: PreviewResult
    }
    private var sliceCache: [Data: CachedSlice] = [:]
    private var sliceCacheOrder: [Data] = []
    private let resource: URL
    let preferences: UserDefaults
    private var engine: NativeSliceEngine?

    init(resource: URL = Bundle.main.resourceURL!, preferences: UserDefaults = .standard) {
        self.resource = resource
        self.preferences = preferences
        backgroundWhite = preferences.bool(forKey: "149.preview.background.white")
        do {
            let data = try Data(contentsOf: BundledResource.definition(BundledResource.defaults, in: resource))
            defaults = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            materialCatalog = try JSONDecoder().decode(
                [PelletMaterial].self,
                from: Data(contentsOf: BundledResource.definition(BundledResource.pelletMaterials, in: resource)))
            engine = try NativeSliceEngine(resources: resource)
            try applyProject(defaults)
            if let name = preferences.string(forKey: "149.lastPrinter"),
                let draft = preferences.dictionary(forKey: "149.machine.fields." + name) as? [String: String]
            {
                fields.merge(
                    draft.filter { $0.key != "ImportFile" && $0.key != "ImportScale" }, uniquingKeysWith: { $1 })
                if fields["SourceMode"] == "Imported" {
                    for (key, value) in defaults["shape"] as! [String: Any] {
                        fields[key] = (value as? NSNumber)?.stringValue ?? String(describing: value)
                    }
                }
            }
            let savedTransform =
                preferences.dictionary(forKey: "149.placement.transform." + printerModel) as? [String: Double]
            placementRotation = preferences.double(forKey: "149.placement.rotation." + printerModel)
            if let offset = preferences.array(forKey: "149.placement.offset." + printerModel) as? [Double],
                offset.count == 2
            {
                placementOffset = SIMD2(offset[0], offset[1])
            }
            if let savedTransform { restorePlacement(savedTransform) }
            prepareMaterialLibrary()
            loadMaterialAppearance()
            savedDocumentData = try documentData()
        } catch { self.error = LF("无法读取内置参数：%@", String(error.localizedDescription)) }
    }
    deinit {
        previewComputation?.cancel()
        for folder in Set(sliceCache.values.map(\.folder)) { try? FileManager.default.removeItem(at: folder) }
        if let folder = tempFolder { try? FileManager.default.removeItem(at: folder) }
    }
    func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { self.fields[key] ?? "" },
            set: { value in
                if key == "SourceMode" {
                    self.selectShape(value)
                    return
                }
                self.fields[key] = value
                if key == "PipeScrollProfile" {
                    let profileDefaults: [String: String] =
                        value == "2"
                        ? ["W": "8", "PipeScrollSpacing": "167.96", "PipeScrollRot": "0", "PipeScrollHeight": "250"]
                        : (value == "1"
                            ? ["W": "6", "PipeScrollSpacing": "215", "PipeScrollRot": "-6.4"]
                            : ["W": "6", "PipeScrollSpacing": "150", "PipeScrollRot": "0"])
                    self.fields.merge(profileDefaults, uniquingKeysWith: { $1 })
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
        var output: [String: Any] = ["version": 1, "placement": placementValues]
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
        if (raw["shape"] as? [String: Any])?["SourceMode"] as? String == "Imported" {
            throw message("此项目使用已移除的模型导入功能，无法打开。")
        }
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
            if let unknown = values.keys.first(where: {
                schema[$0] == nil && !(group == "shape" && ["ImportFile", "ImportScale"].contains($0))
            }) {
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
                "Cylinder", "Ellipse", "Cone", "Triple", "TripleVase", "DoubleScroll", "NonplanarCylinder",
                "Crescent", "SingleBud", "CornerPipe", "EggScroll", "Wardrobe", "TravelTest", "Fern1060", "Fern1060E",
                "PipeScroll", "PelletBottle", "Hopper",
            ].contains(next["SourceMode"] ?? "")
        else { throw message("不支持的造型类型。") }
        let appearance: MaterialAppearance?
        if let rawAppearance = raw["appearance"] {
            appearance = try JSONDecoder().decode(
                MaterialAppearance.self, from: JSONSerialization.data(withJSONObject: rawAppearance))
            guard appearance!.valid else { throw message("材质参数无效。") }
        } else {
            appearance = nil
        }
        let placement = raw["placement"] as? [String: Double] ?? [:]
        guard placement.values.allSatisfy(\.isFinite) else { throw message("摆放参数无效。") }
        finishPlacement()
        fields = next
        restorePlacement(placement)
        prepareMaterialLibrary()
        if let appearance { materialAppearance = appearance } else { loadMaterialAppearance() }
        dirty = true
        savedURL = nil
        documentURL = nil
        shapeDrafts.removeAll()
        selectedEFPresetID = ""
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
            let cached = sliceCache[data]
            let cachedFolder = cached?.folder
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
                    if cachedFolder == nil {
                        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                        let generated = try PlacementRotation.generate(raw, engine: engine, prepared: prepared)
                        try generated.write(to: folder)
                        result = try PreviewResult(native: generated)
                    } else {
                        result = cached!.preview
                    }
                    guard result.ok else { throw self.message("生成失败。") }
                    let elapsed = Date().timeIntervalSince(started)
                    DispatchQueue.main.async {
                        if let previous = self.tempFolder, previous != folder,
                            !self.sliceCache.values.contains(where: { $0.folder == previous })
                        {
                            try? FileManager.default.removeItem(at: previous)
                        }
                        do {
                            self.sliceCache[data] = CachedSlice(folder: folder, preview: result)
                            self.sliceCacheOrder.removeAll { $0 == data }
                            self.sliceCacheOrder.append(data)
                            while self.sliceCacheOrder.count > 3
                                || (self.sliceCache.count > 1
                                    && self.sliceCache.values.reduce(0, { $0 + $1.preview.segments.count }) > 250_000)
                            {
                                let key = self.sliceCacheOrder.removeFirst()
                                if let old = self.sliceCache.removeValue(forKey: key) {
                                    try? FileManager.default.removeItem(at: old.folder)
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
