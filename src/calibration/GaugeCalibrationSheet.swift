import AppKit
import SwiftUI

struct GaugeCalibrationSheet: View {
    @ObservedObject var store: CalibrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var analog = false
    @State private var candidate: [String: Any] = [:]
    @State private var image: NSImage?
    @State private var rotated: NSImage?
    @State private var rotation = 180
    @State private var expected = 0.0
    @State private var markValue = 0.1
    @State private var counterValue = 2.0
    @State private var roi: [Double] = [475.0 / 1280, 340.0 / 720, 712.0 / 1280, 449.0 / 720]
    @State private var points: [String: [Double]] = [:]
    @State private var selectedPoint = "center"
    @State private var status = ""
    @State private var busy = false
    private let pointNames = [
        ("center", "主表中心"), ("zero", "主表零位"), ("mark", "主表刻度"), ("counterCenter", "副表中心"), ("counterZero", "副表零位"),
        ("counterMark", "副表刻度"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                uiText(analog ? "校准指针表" : "校准数显表").font(.title2)
                Spacer()
                Button(L("关闭")) { dismiss() }.disabled(busy)
            }
            HStack {
                Picker(L("读数方式"), selection: $analog) {
                    uiText("数显表").tag(false)
                    uiText("指针表").tag(true)
                }.pickerStyle(.segmented).frame(width: 220)
                Spacer()
                if !analog {
                    Picker(
                        "旋转",
                        selection: Binding(
                            get: { rotation },
                            set: {
                                rotation = $0
                                roi = [0.2, 0.35, 0.8, 0.65]
                                clearReference()
                                updateImage()
                            })
                    ) { ForEach([0, 90, 180, 270], id: \.self) { uiText("\($0)°").tag($0) } }.frame(width: 140)
                }
                Button(L("重新拍摄")) { capture() }
            }.disabled(busy)
            uiText(analog ? "按顺序点击中心、零位和已知刻度；主表与副表分别标定。" : "先将表切到 mm，再框选整排数字、小数点与负号区域，避开单位文字和边框。").font(.callout)
                .foregroundStyle(.secondary)
            if analog {
                HStack {
                    ForEach(pointNames, id: \.0) { key, label in
                        Button(L(label)) { selectedPoint = key }.buttonStyle(.bordered).tint(
                            selectedPoint == key ? .accentColor : nil)
                    }
                }.disabled(busy)
            }
            calibrationImage.frame(height: 330)
            HStack {
                if analog {
                    CalibrationNumberRow("主表刻度", value: $markValue, unit: "mm")
                    CalibrationNumberRow("副表刻度", value: $counterValue, unit: "mm")
                } else {
                    CalibrationNumberRow("表上当前显示值", value: $expected, unit: "mm").frame(width: 300)
                }
                Spacer()
            }.disabled(busy)
            uiText(status.isEmpty ? "移动相机或更换表后需重新校准；扫描期间不要置零或切换单位。" : status).font(.callout).foregroundStyle(.secondary)
                .frame(minHeight: 30, alignment: .leading)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("试读")) { check(save: false) }
                Button(L("核对并保存")) { check(save: true) }
            }.disabled(busy || image == nil)
        }.padding(24).frame(width: 740)
            .interactiveDismissDisabled(busy)
            .onAppear {
                loadCandidate()
                capture()
            }
            .onChange(of: analog) { _ in
                loadCandidate()
                updateImage()
            }
    }
    private var calibrationImage: some View {
        GeometryReader { g in
            if let display = rotated {
                let ratio = display.size.width / display.size.height
                let w = min(g.size.width, g.size.height * ratio)
                let h = w / ratio
                Image(nsImage: display).resizable().frame(width: w, height: h)
                    .overlay {
                        Canvas { context, size in
                            if analog {
                                for (key, label) in pointNames {
                                    if let p = points[key], p.count == 2 {
                                        let x = p[0] * size.width
                                        let y = p[1] * size.height
                                        context.stroke(
                                            Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)),
                                            with: .color(key == selectedPoint ? .yellow : .white), lineWidth: 2)
                                        context.draw(
                                            uiText(label).font(.caption).foregroundColor(.white),
                                            at: CGPoint(x: x + 8, y: y - 10), anchor: .leading)
                                    }
                                }
                            } else {
                                let rect = CGRect(
                                    x: roi[0] * size.width, y: roi[1] * size.height,
                                    width: (roi[2] - roi[0]) * size.width, height: (roi[3] - roi[1]) * size.height)
                                context.stroke(Path(rect), with: .color(.green), lineWidth: 2)
                            }
                        }.contentShape(Rectangle()).gesture(
                            DragGesture(minimumDistance: 0).onChanged { value in
                                guard !busy else { return }
                                func point(_ p: CGPoint) -> [Double] {
                                    [max(0, min(1, p.x / w)), max(0, min(1, p.y / h))]
                                }
                                let start = point(value.startLocation)
                                let end = point(value.location)
                                if analog {
                                    points[selectedPoint] = end
                                } else {
                                    roi = [
                                        min(start[0], end[0]), min(start[1], end[1]), max(start[0], end[0]),
                                        max(start[1], end[1]),
                                    ]
                                }
                                clearReference()
                            }.onEnded { _ in
                                if analog, let i = pointNames.firstIndex(where: { $0.0 == selectedPoint }) {
                                    selectedPoint = pointNames[min(5, i + 1)].0
                                }
                            })
                    }.position(x: g.size.width / 2, y: g.size.height / 2)
            } else {
                ZStack {
                    Color.black.opacity(0.1)
                    uiText("等待相机画面").foregroundStyle(.secondary)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func loadCandidate() {
        let profile = analog ? "white-plunger-10mm-v1" : "katsu-lcd-mm-v1"
        candidate =
            store.calibration["profile"] as? String == profile
            ? store.calibration : ["profile": profile, "width": 1280, "height": 720, "unit": "mm"]
        candidate["confirmed"] = false
        if analog {
            let fallback: [String: [Double]] = [
                "center": [635.0 / 1280, 415.0 / 720], "zero": [768.0 / 1280, 492.0 / 720],
                "mark": [698.0 / 1280, 555.0 / 720], "counterCenter": [654.0 / 1280, 356.0 / 720],
                "counterZero": [650.0 / 1280, 385.0 / 720], "counterMark": [681.0 / 1280, 364.0 / 720],
            ]
            points = fallback.mapValues { $0 }
            for (key, _) in fallback {
                if let saved = candidate[key] as? [Double], saved.count == 2 { points[key] = saved }
            }
            markValue = candidate["markMm"] as? Double ?? 0.1
            counterValue = candidate["counterMarkMm"] as? Double ?? 2
        } else {
            rotation = candidate["rotation"] as? Int ?? 180
            roi = candidate["digitRoi"] as? [Double] ?? [475.0 / 1280, 340.0 / 720, 712.0 / 1280, 449.0 / 720]
        }
        status = ""
    }
    private func clearReference() {
        candidate.removeValue(forKey: "tracking")
        candidate.removeValue(forKey: "unitRoi")
        candidate.removeValue(forKey: "unitBits")
        candidate.removeValue(forKey: "outlineRadius")
        candidate.removeValue(forKey: "outlineCenter")
        candidate["confirmed"] = false
        status = ""
    }
    private func capture() {
        busy = true
        store.request(.camera) { result in
            busy = false
            switch result {
            case .success(let data):
                guard let bytes = data["imageData"] as? Data, let next = NSImage(data: bytes),
                    let bitmap = next.representations.first
                else {
                    status = "无法读取相机画面"
                    return
                }
                image = next
                candidate["width"] = bitmap.pixelsWide
                candidate["height"] = bitmap.pixelsHigh
                updateImage()
            case .failure(let error): status = error.localizedDescription
            }
        }
    }
    private func updateImage() {
        guard let source = image else { return }
        let degrees = analog ? 0 : rotation
        guard degrees != 0 else {
            rotated = source
            return
        }
        let size = source.size
        let sideways = degrees % 180 != 0
        let result = NSImage(size: sideways ? NSSize(width: size.height, height: size.width) : size)
        result.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: result.size.width / 2, yBy: result.size.height / 2)
        transform.rotate(byDegrees: CGFloat(degrees))
        transform.concat()
        source.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        result.unlockFocus()
        rotated = result
    }
    private func check(save: Bool) {
        guard !busy else { return }
        var args = candidate
        if analog {
            guard markValue.isFinite, (0.01...1).contains(markValue), counterValue.isFinite,
                (0.5...3.3).contains(counterValue)
            else {
                status = "请检查主表和副表刻度值"
                return
            }
            for (key, value) in points { args[key] = value }
            args["markMm"] = markValue
            args["counterMarkMm"] = counterValue
        } else {
            guard roi.count == 4, roi[2] - roi[0] > 0.005, roi[3] - roi[1] > 0.005, expected.isFinite else {
                status = "请框选完整数字区域并输入有效读数"
                return
            }
            args["rotation"] = rotation
            args["digitRoi"] = roi
        }
        busy = true
        status = "正在读取…"
        store.request(.needleCheck, params: args) { result in
            switch result {
            case .failure(let error):
                busy = false
                status = error.localizedDescription
            case .success(let data):
                if let error = data["error"] as? String, !error.isEmpty,
                    !(analog && save && error.hasPrefix("Counter is near the 0/10"))
                {
                    busy = false
                    status = error
                    return
                }
                guard let value = data["readingMm"] as? Double, value.isFinite else {
                    busy = false
                    status = "未能识别有效读数"
                    return
                }
                status = String(format: L("%.3f mm · 置信度 %.0f%%"), value, (data["confidence"] as? Double ?? 0) * 100)
                guard save else {
                    busy = false
                    return
                }
                if !analog, abs(value - expected) > 0.005 {
                    busy = false
                    status = "识别结果与输入不一致，请检查框选和单位"
                    return
                }
                args["confirmed"] = true
                if !analog { args["expectedReadingMm"] = expected }
                store.request(.calibrate, params: args) { result in
                    busy = false
                    switch result {
                    case .success:
                        store.message = "读数校准已保存"
                        dismiss()
                    case .failure(let error): status = error.localizedDescription
                    }
                }
            }
        }
    }
}
