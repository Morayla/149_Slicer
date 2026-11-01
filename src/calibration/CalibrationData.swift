import Foundation

func calibrationError(_ text: String) -> NSError {
    NSError(domain: "149.Calibration", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
struct CalibrationConfig: Codable, Equatable {
    var height = 150.0, step = 3.0, lineWidth = 9.0, diameter = 200.0, scanLayers = 15
    var tolerance = 0.1, foot = 1.2, decay = 9.0, speed = 12.0, dwell = 0.65, noise = 0.015
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? height
        step = try c.decodeIfPresent(Double.self, forKey: .step) ?? step
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? lineWidth
        diameter = try c.decodeIfPresent(Double.self, forKey: .diameter) ?? diameter
        scanLayers = try c.decodeIfPresent(Int.self, forKey: .scanLayers) ?? scanLayers
        tolerance = try c.decodeIfPresent(Double.self, forKey: .tolerance) ?? tolerance
        foot = try c.decodeIfPresent(Double.self, forKey: .foot) ?? foot
        decay = try c.decodeIfPresent(Double.self, forKey: .decay) ?? decay
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        dwell = try c.decodeIfPresent(Double.self, forKey: .dwell) ?? dwell
        noise = try c.decodeIfPresent(Double.self, forKey: .noise) ?? noise
    }
    func validated() throws -> Self {
        let values: [(String, Double, ClosedRange<Double>)] = [
            ("样件高度", height, 3...300), ("打印层高", step, 0.5...20), ("打印线宽", lineWidth, 0.5...30),
            ("外径", diameter, 120...300), ("偏差阈值", tolerance, 0.01...5), ("象脚外扩", foot, 0...5), ("衰减高度", decay, 1...60),
            ("下降速度", speed, 1...60), ("停稳时间", dwell, 0.2...5), ("模拟噪声", noise, 0...0.1),
        ]
        for (label, value, range) in values where !value.isFinite || !range.contains(value) {
            throw calibrationError(
                LF("%@超出范围 %@–%@", String(label), String(range.lowerBound), String(range.upperBound)))
        }
        guard (1...100).contains(scanLayers) else { throw calibrationError("测量层数必须为 1–100 的整数") }
        guard lineWidth >= step else { throw calibrationError("打印线宽不能小于层高") }
        var result = self
        result.decay = min(decay, height)
        return result
    }
    var plan: [CalibrationPoint] {
        let count = min(scanLayers, Int(ceil(height / step - 1e-9)))
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let lo = Double(i) * step
            let hi = min(height, Double(i + 1) * step)
            return CalibrationPoint(
                layer: i + 1, heightMm: height - (lo + hi) / 2, printHeightMm: (lo + hi) / 2, thicknessMm: hi - lo)
        }
    }
    var reachable: Bool { !plan.isEmpty && plan.allSatisfy { (104.626407107...212.426407107).contains($0.heightMm) } }
    func radialError(at height: Double) -> Double { foot * exp(-(self.height - height) / decay) }
    func reading(_ point: CalibrationPoint) -> Double {
        let value =
            radialError(at: point.heightMm) + noise
            * (0.65 * sin(Double(point.layer) * 2.137) + 0.35 * sin(Double(point.layer) * 0.831))
        return calibrationRounded(value, digits: 4)
    }
}
struct CalibrationPoint {
    var layer: Int
    var heightMm: Double
    var printHeightMm: Double
    var thicknessMm: Double
}
struct CalibrationSample: Codable, Identifiable, Equatable {
    var layer: Int, heightMm: Double, printHeightMm: Double?, radialErrorMm: Double, timestamp: String, source: String
    var id: Int { layer }
    enum CodingKeys: String, CodingKey {
        case layer, heightMm, printHeightMm, radialErrorMm, compensationMm, timestamp, source
    }
    init(layer: Int, heightMm: Double, printHeightMm: Double?, radialErrorMm: Double, timestamp: String, source: String)
    {
        self.layer = layer
        self.heightMm = heightMm
        self.printHeightMm = printHeightMm
        self.radialErrorMm = radialErrorMm
        self.timestamp = timestamp
        self.source = source
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layer = try c.decode(Int.self, forKey: .layer)
        heightMm = try c.decode(Double.self, forKey: .heightMm)
        printHeightMm = try c.decodeIfPresent(Double.self, forKey: .printHeightMm)
        radialErrorMm = try c.decode(Double.self, forKey: .radialErrorMm)
        timestamp = try c.decode(String.self, forKey: .timestamp)
        source = try c.decode(String.self, forKey: .source)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layer, forKey: .layer)
        try c.encode(heightMm, forKey: .heightMm)
        try c.encodeIfPresent(printHeightMm, forKey: .printHeightMm)
        try c.encode(radialErrorMm, forKey: .radialErrorMm)
        try c.encode(compensationMm, forKey: .compensationMm)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(source, forKey: .source)
    }
    var compensationMm: Double { calibrationRounded(-radialErrorMm, digits: 4) }
    func validate() throws {
        guard (1...10000).contains(layer), heightMm.isFinite, (0...10000).contains(heightMm), radialErrorMm.isFinite,
            abs(radialErrorMm) <= 100, ["simulation", "device", "replay"].contains(source)
        else { throw calibrationError("测量记录的层号、高度、偏差或来源无效") }
        if let z = printHeightMm, !z.isFinite || z < 0 { throw calibrationError("原始打印高度无效") }
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard date.date(from: timestamp) != nil || ISO8601DateFormatter().date(from: timestamp) != nil else {
            throw calibrationError("测量记录时间无效")
        }
    }
}
struct CalibrationRecord: Codable {
    var schema = "elephant-foot.measurement.v1", application = "149 calibration", version = 3, units = "mm",
        mode = "simulation"
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var specimenOrientation = "inverted: print base at physical top"
    var config: CalibrationConfig, samples: [CalibrationSample], excludedLayers: [Int]
    init(config: CalibrationConfig, samples: [CalibrationSample], excluded: Set<Int>, mode: String) {
        self.config = config
        self.samples = samples
        excludedLayers = excluded.sorted()
        self.mode = mode
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count < 5_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["schema"] as? String == "elephant-foot.measurement.v1",
            let rawSamples = object["samples"] as? [[String: Any]], rawSamples.count <= 10000
        else { throw calibrationError("不是支持的测量记录文件，或文件超过 5 MB") }
        let decoder = JSONDecoder()
        let config = try decoder.decode(
            CalibrationConfig.self, from: JSONSerialization.data(withJSONObject: object["config"] ?? [:])
        ).validated()
        let samples = try decoder.decode(
            [CalibrationSample].self, from: JSONSerialization.data(withJSONObject: rawSamples))
        var ids = Set<Int>()
        for row in samples {
            try row.validate()
            guard ids.insert(row.layer).inserted, row.layer <= Int(ceil(config.height / config.step)),
                row.heightMm <= config.height + 0.001
            else {
                throw calibrationError("记录层号重复，或测量高度超出样件")
            }
        }
        var excluded = Set<Int>()
        if let raw = object["excludedLayers"] {
            let numbers = try decoder.decode([Int].self, from: JSONSerialization.data(withJSONObject: raw))
            guard numbers.allSatisfy({ (1...10000).contains($0) }) else { throw calibrationError("排除层号无效") }
            excluded = Set(numbers)
        }
        return Self(config: config, samples: samples, excluded: excluded, mode: "replay")
    }
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    func csv() -> String {
        let header =
            "layer,height_mm,original_print_height_mm,radial_error_mm,radial_compensation_mm,timestamp,source,included"
        return "\u{FEFF}"
            + ([header]
            + samples.map { r in
                [
                    String(r.layer), String(format: "%.3f", r.heightMm),
                    r.printHeightMm.map { String(format: "%.3f", $0) } ?? "", String(format: "%.4f", r.radialErrorMm),
                    String(format: "%.4f", r.compensationMm), r.timestamp, r.source,
                    String(!excludedLayers.contains(r.layer)),
                ].joined(separator: ",")
            }).joined(separator: "\r\n")
    }
}
struct CalibrationSimulation {
    enum Phase: String { case ready, moving, settling, done }
    var config: CalibrationConfig
    var rows: [CalibrationSample] = [], index = 0, phase: Phase = .ready, paused = false, elapsed = 0.0,
        position: Double
    init(config: CalibrationConfig = CalibrationConfig()) {
        self.config = config
        position = config.plan.first?.heightMm ?? 0
    }
    var running: Bool { (phase == .moving || phase == .settling) && !paused }
    mutating func start() {
        if phase == .done { self = Self(config: config) }
        if phase == .ready { phase = .settling }
        paused = false
    }
    mutating func tick(_ delta: Double) {
        guard running, delta.isFinite, delta > 0 else { return }
        var remaining = min(delta, 1)
        let plan = config.plan
        while remaining > 1e-8 && running && index < plan.count {
            let target = plan[index]
            if phase == .moving {
                let distance = target.heightMm - position
                let time = abs(distance) / config.speed
                let used = min(remaining, time)
                position += (distance < 0 ? -1 : 1) * used * config.speed
                remaining -= used
                if time <= used + 1e-8 {
                    position = target.heightMm
                    phase = .settling
                    elapsed = 0
                } else {
                    break
                }
            } else {
                let used = min(remaining, config.dwell - elapsed)
                elapsed += used
                remaining -= used
                if elapsed >= config.dwell - 1e-8 {
                    rows.append(
                        CalibrationSample(
                            layer: target.layer, heightMm: target.heightMm, printHeightMm: target.printHeightMm,
                            radialErrorMm: config.reading(target),
                            timestamp: ISO8601DateFormatter().string(from: Date()), source: "simulation"))
                    index += 1
                    elapsed = 0
                    phase = index == plan.count ? .done : .moving
                } else {
                    break
                }
            }
        }
    }
}
struct CalibrationTarget: Equatable {
    var height: Double, layerHeight: Double, lineWidth: Double, baseHeight: Double, diameter: Double, eligible: Bool
}
struct CalibrationDraft {
    var amount: Double, turns: Int, table: String, baseline: Double, simulated: Bool, usedLayers: Int,
        target: CalibrationTarget
    static func make(
        config: CalibrationConfig, samples: [CalibrationSample], target: CalibrationTarget, excluded: Set<Int>
    ) throws -> Self {
        let rows = samples.filter { !excluded.contains($0.layer) }.sorted {
            config.height - $0.heightMm < config.height - $1.heightMm
        }
        guard rows.count >= 5 else { throw calibrationError("至少需要五层有效记录") }
        guard target.eligible else { throw calibrationError("当前造型不支持这项补偿") }
        guard [target.layerHeight, target.baseHeight, target.height, target.lineWidth].allSatisfy({ $0.isFinite }),
            target.layerHeight > 0
        else { throw calibrationError("切片参数无效") }
        let tail = rows.suffix(3).map(\.radialErrorMm).sorted()
        let baseline = tail[1]
        guard tail[2] - tail[0] <= config.tolerance else { throw calibrationError("尾部读数尚未稳定，请增加测量范围") }
        var blocks: [(sum: Double, n: Int)] = []
        for row in rows {
            blocks.append((max(0, row.radialErrorMm - baseline), 1))
            while blocks.count > 1 {
                let a = blocks[blocks.count - 2]
                let b = blocks.last!
                guard a.sum / Double(a.n) < b.sum / Double(b.n) else { break }
                blocks.removeLast(2)
                blocks.append((a.sum + b.sum, a.n + b.n))
            }
        }
        let fit = blocks.flatMap { Array(repeating: $0.sum / Double($0.n), count: $0.n) }
        let z = rows.map { config.height - $0.heightMm }
        func at(_ height: Double) -> Double {
            if height <= z[0] { return fit[0] }
            for i in 1..<z.count where height <= z[i] {
                let t = (height - z[i - 1]) / (z[i] - z[i - 1])
                return fit[i - 1] * (1 - t) + fit[i] * t
            }
            return fit.last!
        }
        let turns = Int(floor((z.last! - target.baseHeight) / target.layerHeight))
        guard (1...200).contains(turns), target.baseHeight + Double(turns) * target.layerHeight <= target.height else {
            throw calibrationError("有效记录不足以覆盖当前切片的墙体圈数")
        }
        let amount = at(target.baseHeight)
        guard amount >= 0.001 else { throw calibrationError("当前记录没有足够的外扩量生成补偿") }
        guard amount <= min(config.lineWidth, target.lineWidth) / 2 else { throw calibrationError("补偿量超过半个线宽，请复核读数") }
        let table = (0...turns).map { i -> String in
            let p =
                i == 0
                ? 100
                : i == turns
                    ? 0
                    : calibrationRounded(
                        100 * at(target.baseHeight + Double(i) * target.layerHeight) / amount, digits: 5)
            return "\(i):\(p)"
        }.joined(separator: "\n")
        return Self(
            amount: calibrationRounded(amount, digits: 4), turns: turns, table: table, baseline: baseline,
            simulated: rows.contains { $0.source != "device" }, usedLayers: rows.count, target: target)
    }
}

// Match ECMAScript toFixed without first rounding the binary product value*10^digits.
// This preserves historical records at decimal boundaries (including exact binary ties).
func calibrationRounded(_ value: Double, digits: Int) -> Double {
    guard value.isFinite, (0...6).contains(digits), abs(value) < 1e12 else { return value }
    let bits = abs(value).bitPattern
    let exponent = Int((bits >> 52) & 0x7ff)
    let mantissa = (bits & 0x000f_ffff_ffff_ffff) | (exponent == 0 ? 0 : 0x0010_0000_0000_0000)
    let power = exponent == 0 ? -1074 : exponent - 1023 - 52
    var five: UInt64 = 1
    for _ in 0..<digits { five *= 5 }
    let product = mantissa.multipliedFullWidth(by: five)
    let shift = -(power + digits)
    guard shift > 0 else { return value }
    var quotient: UInt64 = 0
    var up = false
    if shift < 64 {
        quotient = (product.high << (64 - shift)) | (product.low >> shift)
        up = (product.low & ((UInt64(1) << shift) - 1)) >= (UInt64(1) << (shift - 1))
    } else if shift == 64 {
        quotient = product.high
        up = product.low >= (UInt64(1) << 63)
    } else if shift < 128 {
        let highShift = shift - 64
        quotient = product.high >> highShift
        up = (product.high & ((UInt64(1) << highShift) - 1)) >= (UInt64(1) << (highShift - 1))
    }
    if up { quotient += 1 }
    return (value < 0 ? -1 : 1) * Double(quotient) / pow(10, Double(digits))
}
