import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class CalibrationStore: ObservableObject {
    enum Workspace: String, CaseIterable {
        case device = "实机"
        case simulation = "样件与演示"
    }
    @Published var loading = true
    @Published var baseHeight = 2.5
    let hardware: ScannerHardware
    let renderer = CalibrationRenderer()
    @Published var workspace: Workspace = .device
    @Published var config = CalibrationConfig()
    @Published var simulation = CalibrationSimulation()
    @Published var excluded = Set<Int>()
    @Published var selectedLayer: Int?
    @Published var recordMode = "simulation"
    @Published var message = ""
    @Published var error = ""
    @Published var active = false
    @Published var sidebarVisible = true
    @Published var resultsVisible = true
    @Published var presentation = false
    @Published var showDiscard = false
    @Published var showDraft = false
    @Published var showCalibration = false
    @Published var showCamera = false
    @Published var draft: CalibrationDraft?
    @Published var status: [String: Any] = [:]
    @Published var connected = false
    @Published var sending = false
    @Published var cameraImage: NSImage?
    @Published var cameraDate = Date.distantPast
    @Published var liveValue: Double?
    @Published var liveQuality = "等待读数"
    @Published var travelSpeed = 0.8
    @Published var jogDistance = 1.0
    @Published var scanSpacing = 4.0
    @Published var scanCount = 10
    @Published var scanDwell = 3.0
    @Published var scanDirection = "away"
    @Published var smallThreshold = 0.01
    @Published var sceneMode = "clay"
    @Published var cameraView = "iso"
    @Published var xrayWhite = true
    @Published var lineStrength = 0.55
    @Published var grain = 0.085
    @Published var electronicsVisible = true
    @Published var wiresVisible = true
    @Published var electronicsOpen = false
    private var timer: Timer?, simulationTimer: Timer?, lastTick = Date(), lastCameraPoll = Date.distantPast,
        lastNeedlePoll = Date.distantPast
    private var statusPending = false, cameraPending = false, needlePending = false, motionObserved = false
    private(set) var ownsMotion = false
    private var lastStatusPoll = Date.distantPast
    private var pendingAction: (() -> Void)?, sessionURL: URL?
    private var liveSamples: [(Double, Date, Bool)] = []
    private var archivedDeviceScan: [String: Any]?
    init(hardware: ScannerHardware = ScannerHardware()) {
        self.hardware = hardware
        let defaults = UserDefaults.standard
        if defaults.data(forKey: "149.native.calibration.record") == nil {
            let legacy = CalibrationMigration.read(bundleIdentifier: "local.g1mini.workbench")
            if let text = legacy["149-calibration-session"] {
                defaults.set(Data(text.utf8), forKey: "149.native.calibration.record")
            }
            for key in ["view", "xray-background", "camera", "line-contrast", "sidebar"] {
                if let value = legacy["149-calibration-" + key] {
                    defaults.set(value, forKey: "149.native.calibration." + key)
                }
            }
            if let value = legacy["149-travel-speed"].flatMap(Double.init) {
                defaults.set(value, forKey: "149.native.calibration.travelSpeed")
            }
            if let value = legacy["149-small-change-threshold"].flatMap(Double.init) {
                defaults.set(value, forKey: "149.native.calibration.threshold")
            }
        }
        if let value = defaults.string(forKey: "149.native.calibration.view"),
            ["clay", "lines", "xray"].contains(value)
        {
            sceneMode = value
        }
        if let value = defaults.string(forKey: "149.native.calibration.camera"),
            ["iso", "front", "side", "top"].contains(value)
        {
            cameraView = value
        }
        xrayWhite = defaults.string(forKey: "149.native.calibration.xray-background") != "black"
        sidebarVisible = defaults.string(forKey: "149.native.calibration.sidebar") != "true"
        if let value = defaults.string(forKey: "149.native.calibration.line-contrast").flatMap(Double.init),
            (0.15...1).contains(value)
        {
            lineStrength = value
        }
        if let value = defaults.object(forKey: "149.native.calibration.threshold") as? Double,
            (0.001...0.1).contains(value)
        {
            smallThreshold = value
        }
        if let data = defaults.data(forKey: "149.native.calibration.record"),
            let saved = try? CalibrationRecord.decode(data)
        {
            config = saved.config
            simulation = CalibrationSimulation(config: config)
            simulation.rows = saved.samples
            excluded = Set(saved.excludedLayers)
            recordMode = saved.samples.isEmpty ? "simulation" : "replay"
            simulation.position = saved.samples.last?.heightMm ?? simulation.position
        }
        workspace =
            defaults.string(forKey: "149.native.calibration.workspace").flatMap(Workspace.init(rawValue:))
            ?? (rows.isEmpty ? .device : .simulation)
        if let saved = defaults.object(forKey: "149.native.calibration.travelSpeed") as? Double, saved.isFinite,
            saved >= 0.1
        {
            travelSpeed = saved
        }
        renderer.load { [weak self] result in
            guard let self = self else { return }
            self.loading = false
            if case .failure(let error) = result {
                self.error = error.localizedDescription
            } else {
                self.objectWillChange.send()
            }
        }
    }
    deinit {
        timer?.invalidate()
        simulationTimer?.invalidate()
    }
    var rows: [CalibrationSample] { simulation.rows }
    var currentLayer: Int {
        selectedLayer ?? (recordMode != "simulation" ? rows.last?.layer : nil)
            ?? simulation.config.plan[min(simulation.index, max(0, simulation.config.plan.count - 1))].layer
    }
    var currentSample: CalibrationSample? { rows.first { $0.layer == currentLayer } }
    var currentHeight: Double { currentSample?.heightMm ?? simulation.position }
    var currentError: Double? {
        currentSample?.radialErrorMm
            ?? (recordMode == "simulation" ? simulation.config.radialError(at: simulation.position) : nil)
    }
    var busy: Bool { (status["busy"] as? Bool ?? false) || sending }
    var homed: Bool { status["homed"] as? Bool ?? false }
    var limitPressed: Bool { status["limitPressed"] as? Bool ?? false }
    var compatible: Bool {
        status["setupId"] as? String == "bottom-white-v1" && status["limitEnd"] as? String == "bottom"
            && (status["towardDir"] as? Int) == 1
    }
    var canMove: Bool { connected && compatible && !busy && homed && !limitPressed }
    var calibration: [String: Any] { status["calibration"] as? [String: Any] ?? [:] }
    var calibrationConfirmed: Bool {
        (["white-plunger-10mm-v1", "katsu-lcd-mm-v1"].contains(calibration["profile"] as? String ?? ""))
            && calibration["confirmed"] as? Bool == true
    }
    var canScan: Bool { canMove && calibrationConfirmed }
    var deviceScan: [String: Any] { archivedDeviceScan ?? status["scan"] as? [String: Any] ?? [:] }
    var deviceRows: [[String: Any]] { deviceScan["rows"] as? [[String: Any]] ?? [] }
    var deviceTotal: Int { (deviceScan["config"] as? [String: Any])?["count"] as? Int ?? scanCount }
    var phaseText: String {
        let phase = status["phase"] as? String ?? ""
        return [
            "settling": "停稳中", "reading": "读取数值", "reading-extended": "延长采样", "scan-moving": "移动中", "home": "返回原点",
            "reference": "校准下限位", "retreat": "退离限位", "home-position": "返回原点", "jog": "移动中", "complete": "完成",
            "stopped": "已停止", "idle": homed ? "就绪" : "等待归零",
        ][phase] ?? "未连接"
    }
    var scanGate: String {
        !connected
            ? "设备未连接"
            : !compatible
                ? "设备配置不匹配"
                : busy
                    ? phaseText : !calibrationConfirmed ? "请先校准读数" : !homed ? "请先回原点" : limitPressed ? "下限位已触发" : "就绪"
    }
    var simulationPhase: String {
        if recordMode != "simulation" { return "记录回放" }
        return simulation.paused
            ? "已暂停" : [.ready: "就绪", .moving: "移动中", .settling: "停稳中", .done: "完成"][simulation.phase] ?? ""
    }
    var cameraFresh: Bool { Date().timeIntervalSince(cameraDate) < 3.5 }
    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        renderer.setActive(value)
        timer?.invalidate()
        timer = nil
        if value {
            poll()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        } else {
            pause()
            stash()
            if ownsMotion { stop() }
        }
    }
    func pause() {
        simulation.paused = true
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
    func toggleSimulation() {
        if simulation.running {
            pause()
            return
        }
        if recordMode != "simulation" || simulation.phase == .done {
            replaceRecords { [weak self] in
                self?.resetNow()
                self?.startSimulation()
            }
        } else {
            startSimulation()
        }
    }
    private func startSimulation() {
        guard simulation.config.reachable else {
            error = "测量范围超出当前装置行程（104.63–212.43 mm）"
            return
        }
        selectedLayer = nil
        simulation.start()
        lastTick = Date()
        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.active, self.renderer.view?.window?.occlusionState.contains(.visible) != false else {
                self.pause()
                return
            }
            let now = Date()
            let before = self.rows.count
            self.simulation.tick(min(0.1, now.timeIntervalSince(self.lastTick)))
            self.lastTick = now
            if self.rows.count != before { self.stash() }
            if !self.simulation.running {
                self.simulationTimer?.invalidate()
                self.simulationTimer = nil
            }
        }
    }
    func replaceRecords(_ action: @escaping () -> Void) {
        pause()
        if rows.isEmpty {
            action()
        } else {
            pendingAction = action
            showDiscard = true
        }
    }
    func confirmReplace() {
        let action = pendingAction
        pendingAction = nil
        showDiscard = false
        action?()
    }
    func reset() { replaceRecords { [weak self] in self?.resetNow() } }
    private func resetNow() {
        simulation = CalibrationSimulation(config: config)
        excluded = []
        selectedLayer = nil
        draft = nil
        recordMode = "simulation"
        stash()
    }
    func applyConfig() {
        do {
            let next = try config.validated()
            replaceRecords { [weak self] in
                self?.config = next
                self?.resetNow()
            }
        } catch { self.error = error.localizedDescription }
    }
    func toggleExcluded(_ layer: Int) {
        if excluded.contains(layer) { excluded.remove(layer) } else { excluded.insert(layer) }
        draft = nil
        stash()
    }
    private var record: CalibrationRecord {
        CalibrationRecord(config: simulation.config, samples: rows, excluded: excluded, mode: recordMode)
    }
    func persistDisplay() {
        let defaults = UserDefaults.standard
        for (key, value) in [
            "view": sceneMode, "camera": cameraView, "xray-background": xrayWhite ? "white" : "black",
            "line-contrast": String(lineStrength), "sidebar": String(!sidebarVisible), "workspace": workspace.rawValue,
        ] { defaults.set(value, forKey: "149.native.calibration." + key) }
        if smallThreshold.isFinite, (0.001...0.1).contains(smallThreshold) {
            defaults.set(smallThreshold, forKey: "149.native.calibration.threshold")
        }
    }
    var displayKey: String {
        "\(sceneMode):\(cameraView):\(xrayWhite):\(lineStrength):\(sidebarVisible):\(smallThreshold):\(workspace.rawValue)"
    }
    func stash() {
        if let data = try? record.data() { UserDefaults.standard.set(data, forKey: "149.native.calibration.record") }
    }
    func save(asNew: Bool = false) {
        pause()
        do {
            var object = try JSONSerialization.jsonObject(with: record.data()) as! [String: Any]
            if !deviceScan.isEmpty { object["deviceScan"] = deviceScan }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            if !asNew, let url = sessionURL {
                try data.write(to: url, options: .atomic)
                message = "测量记录已保存"
                return
            }
            saveData(data, name: sessionURL?.lastPathComponent ?? "149-calibration.json", type: .json, remember: true)
        } catch { self.error = error.localizedDescription }
    }
    func open() {
        pause()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let record = try CalibrationRecord.decode(data)
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            replaceRecords { [weak self] in
                guard let self = self else { return }
                self.config = record.config
                self.simulation = CalibrationSimulation(config: record.config)
                self.simulation.rows = record.samples
                self.simulation.position = record.samples.last?.heightMm ?? self.simulation.position
                self.excluded = Set(record.excludedLayers)
                self.recordMode = "replay"
                self.selectedLayer = nil
                self.sessionURL = url
                self.archivedDeviceScan = raw?["deviceScan"] as? [String: Any]
                self.workspace = self.archivedDeviceScan == nil ? .simulation : .device
                self.stash()
                self.message = "测量记录已载入"
            }
        } catch { self.error = error.localizedDescription }
    }
    func exportCSV() {
        pause()
        if workspace == .device {
            guard !deviceRows.isEmpty else {
                error = "没有可导出的实机记录"
                return
            }
            let keys = [
                "point", "offsetMm", "positionMm", "readingMm", "deltaMm", "previousDeltaMm", "frames", "spreadMm",
                "confidence", "capturedAt", "rejectedFrames", "dwellActualSeconds", "counterMm", "fractionalMm",
                "displayText", "unit", "method", "resolutionMm",
            ]
            func cell(_ value: Any?) -> String {
                let text = value.map { String(describing: $0) } ?? ""
                return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            let csv =
                ([keys.joined(separator: ",")]
                + deviceRows.map { row in keys.map { cell(row[$0]) }.joined(separator: ",") }).joined(separator: "\r\n")
            saveData(Data(csv.utf8), name: "149-camera-scan.csv", type: .commaSeparatedText)
        } else {
            guard !rows.isEmpty else {
                error = "没有可导出的测量记录"
                return
            }
            saveData(Data(record.csv().utf8), name: "149-measurement.csv", type: .commaSeparatedText)
        }
    }
    private func saveData(_ data: Data, name: String, type: UTType, remember: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            if remember { sessionURL = url }
            message = "已保存：" + url.lastPathComponent
        } catch { self.error = error.localizedDescription }
    }
    func reviewDraft() {
        pause()
        draft = nil
        showDraft = true
        error = ""
        do {
            if recordMode == "simulation", simulation.phase != .done { throw calibrationError("请先完成模拟测量") }
            draft = try CalibrationDraft.make(
                config: simulation.config, samples: rows, target: compensationTarget, excluded: excluded)
        } catch { self.error = error.localizedDescription }
    }
    private var compensationTarget: CalibrationTarget {
        let c = simulation.config
        return CalibrationTarget(
            height: c.height, layerHeight: c.step, lineWidth: c.lineWidth, baseHeight: baseHeight, diameter: c.diameter,
            eligible: true)
    }
    func exportDraft() {
        do {
            let value = try CalibrationDraft.make(
                config: simulation.config, samples: rows, target: compensationTarget, excluded: excluded)
            let preset = CompensationPreset(
                name: value.simulated ? "模拟测量补偿" : "实测补偿",
                fields: [
                    "EF": String(value.amount), "EFLayers": String(value.turns), "EFTable": value.table,
                    "EFEnabled": "0",
                ])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            saveData(try encoder.encode(preset), name: "149-compensation.json", type: .json)
        } catch { self.error = error.localizedDescription }
    }
    func request(
        _ command: ScannerCommand, params: [String: Any] = [:],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        var args = params
        if command.requiresSetup {
            guard compatible else {
                completion(.failure(calibrationError(L("设备配置不匹配，请连接下限位控制器"))))
                return
            }
            args["setupId"] = "bottom-white-v1"
        }
        hardware.request(command, params: args, completion: completion)
    }
    func motion(_ method: ScannerCommand, params: [String: Any] = [:]) {
        guard !busy else { return }
        guard travelSpeed.isFinite, travelSpeed >= 0.1 else {
            error = "移动速度必须不小于 0.10 mm/s"
            return
        }
        var args = params
        args["speedMmS"] = travelSpeed
        sending = true
        error = ""
        ownsMotion = true
        motionObserved = false
        archivedDeviceScan = nil
        UserDefaults.standard.set(travelSpeed, forKey: "149.native.calibration.travelSpeed")
        request(method, params: args) { [weak self] result in
            guard let self = self else { return }
            self.sending = false
            if case .failure(let e) = result {
                self.error = e.localizedDescription
                self.stop()
            }
            self.pollStatus()
        }
    }
    func jog(_ direction: String) {
        guard canMove, jogDistance.isFinite, (0.1...10).contains(jogDistance) else {
            error = "移动距离必须为 0.1–10 mm"
            return
        }
        motion(.jog, params: ["mm": jogDistance, "direction": direction])
    }
    func startDeviceScan() {
        guard canScan, scanSpacing.isFinite, (0.1...10).contains(scanSpacing), (2...30).contains(scanCount),
            scanDwell.isFinite, (3...10).contains(scanDwell)
        else {
            error = "请检查设备状态和扫描范围"
            return
        }
        motion(
            .scan,
            params: ["stepMm": scanSpacing, "count": scanCount, "dwellSeconds": scanDwell, "direction": scanDirection])
    }
    func stop(completion: ((Bool) -> Void)? = nil) {
        request(.stop) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.error = error.localizedDescription
                completion?(false)
            case .success:
                self?.ownsMotion = false
                completion?(true)
            }
            self?.pollStatus()
        }
    }
    func stopBeforeQuitting(_ completion: @escaping (Bool) -> Void) {
        // Wait for an outstanding motion command before sending its stop.
        if sending {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.stopBeforeQuitting(completion) }
        } else {
            stop(completion: completion)
        }
    }
    func saveHome(_ mode: String) {
        guard !busy else { return }
        sending = true
        request(.homePosition, params: ["mode": mode]) { [weak self] result in
            self?.sending = false
            if case .failure(let e) = result {
                self?.error = e.localizedDescription
            } else {
                self?.message = "Home 原点设置已保存；设备未移动"
            }
            self?.pollStatus()
        }
    }
    func clearDeviceScan() {
        guard !busy else { return }
        archivedDeviceScan = nil
        request(.scanClear) { [weak self] result in
            if case .failure(let e) = result { self?.error = e.localizedDescription }
            self?.pollStatus()
        }
    }
    private func poll() {
        guard active else { return }
        if Date().timeIntervalSince(lastStatusPoll) >= 1 { pollStatus() }
        guard renderer.view?.window?.occlusionState.contains(.visible) != false, workspace == .device else { return }
        if Date().timeIntervalSince(lastCameraPoll) >= 0.5, !showCalibration { pollCamera() }
        if Date().timeIntervalSince(lastNeedlePoll) >= 0.7, !busy, !showCalibration, calibrationConfirmed {
            pollNeedle()
        }
    }
    private func pollStatus() {
        guard !statusPending else { return }
        statusPending = true
        lastStatusPoll = Date()
        request(.status) { [weak self] result in
            guard let self = self else { return }
            self.statusPending = false
            switch result {
            case .success(let data):
                if !NSDictionary(dictionary: self.status).isEqual(to: data) { self.status = data }
                if !self.connected { self.connected = true }
                if self.ownsMotion, data["busy"] as? Bool == true { self.motionObserved = true }
                if self.motionObserved, data["busy"] as? Bool == false {
                    self.ownsMotion = false
                    self.motionObserved = false
                }
            case .failure:
                if self.connected { self.connected = false }
                if self.liveValue != nil { self.liveValue = nil }
                self.liveSamples = []
            }
        }
    }
    private func pollCamera() {
        guard !cameraPending else { return }
        cameraPending = true
        lastCameraPoll = Date()
        request(.camera) { [weak self] result in
            guard let self = self else { return }
            self.cameraPending = false
            if case .success(let data) = result, let bytes = data["imageData"] as? Data,
                let image = NSImage(data: bytes)
            {
                self.cameraImage = image
                self.cameraDate = Date()
            }
        }
    }
    private func pollNeedle() {
        guard !needlePending, connected else { return }
        needlePending = true
        lastNeedlePoll = Date()
        request(.needle) { [weak self] result in
            guard let self = self else { return }
            self.needlePending = false
            guard case .success(let data) = result, let value = data["readingMm"] as? Double, value.isFinite,
                let confidence = data["confidence"] as? Double
            else {
                self.liveSamples = []
                self.liveValue = nil
                self.liveQuality = "等待有效读数"
                return
            }
            let digital = data["method"] as? String == "lcd-seven-segment"
            let now = Date()
            guard confidence >= (digital ? 0.65 : 0.35) else {
                self.liveValue = nil
                self.liveSamples = []
                self.liveQuality = "读数置信度不足"
                return
            }
            if self.liveSamples.first?.2 != digital { self.liveSamples = [] }
            self.liveSamples = self.liveSamples.filter { now.timeIntervalSince($0.1) <= 4 }
            self.liveSamples.append((value, now, digital))
            self.liveSamples = Array(self.liveSamples.suffix(5))
            let values = self.liveSamples.map { $0.0 }.sorted()
            self.liveValue = nil
            if values.count < 3 {
                self.liveQuality = "等待读数稳定"
            } else if values.last! - values.first! > (digital ? 0.010001 : 0.003) {
                self.liveQuality = "读数波动中"
            } else {
                let mid = values.count / 2
                self.liveValue = digital || values.count % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2
                self.liveQuality = "读数稳定"
            }
        }
    }
}
