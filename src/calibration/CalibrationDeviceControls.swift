import SwiftUI

struct CalibrationCameraView: View {
    @ObservedObject var store: CalibrationStore
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.15))
            if let image = store.cameraImage, store.cameraFresh {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .rotationEffect(
                        .degrees(
                            store.calibration["profile"] as? String == "katsu-lcd-mm-v1"
                                ? -(store.calibration["rotation"] as? Double ?? 180) : 0))
            } else {
                Label(L(store.connected ? "等待相机画面" : "相机未连接"), systemImage: "video.slash").font(.caption)
                    .foregroundStyle(
                        .secondary)
            }
        }.clipped()
    }
}
struct CalibrationDeviceControls: View {
    @ObservedObject var store: CalibrationStore
    var body: some View {
        Group {
            HStack {
                uiText("相机").font(.headline)
                Spacer()
                Button {
                    store.showCamera = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }.buttonStyle(.borderless).help(L("放大画面"))
            }
            CalibrationCameraView(store: store).frame(height: 130)
            HStack {
                Circle().fill(store.connected ? Color.green : Color.secondary).frame(width: 6, height: 6)
                uiText(store.connected ? "扫描设备已连接" : "扫描设备未连接").font(.caption)
            }
            CalibrationNumberRow("移动速度", value: $store.travelSpeed, unit: "mm/s").disabled(store.busy)
            Divider()
            uiText("自动扫描").font(.headline)
            HStack {
                uiText(store.liveValue.map { String(format: "%.3f mm", $0) } ?? "—").font(.title3).monospacedDigit()
                Spacer()
                Button(L("校准读数")) { store.showCalibration = true }.disabled(!store.connected || store.busy)
            }
            uiText(store.liveQuality).font(.caption).foregroundStyle(.secondary)
            CalibrationNumberRow("测点间距", value: $store.scanSpacing, unit: "mm").disabled(store.busy)
            HStack {
                uiText("测点数量")
                Spacer()
                TextField(L("测点数量"), value: $store.scanCount, format: .number).frame(width: 65).multilineTextAlignment(
                    .trailing)
                uiText("点").font(.caption).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            }.disabled(store.busy)
            CalibrationNumberRow("停稳时间", value: $store.scanDwell, unit: "s").disabled(store.busy)
            Picker(L("方向"), selection: $store.scanDirection) {
                uiText("↑ 远离下限位").tag("away")
                uiText("↓ 靠近下限位").tag("toward")
            }.disabled(store.busy)
            uiText(String(format: L("总行程 %.1f mm"), Double(max(0, store.scanCount - 1)) * store.scanSpacing)).font(
                .caption
            ).foregroundStyle(.secondary)
            Divider()
            uiText("设备移动").font(.headline)
            HStack {
                Button(L("回原点")) { store.motion(.home) }.disabled(
                    !store.connected || !store.compatible || store.busy || store.limitPressed)
                Spacer()
                Button(L("停止"), role: .destructive) { store.stop() }.disabled(!store.connected)
            }
            CalibrationNumberRow("移动距离", value: $store.jogDistance, unit: "mm").disabled(store.busy)
            HStack {
                ForEach([0.1, 1, 5, 10], id: \.self) { value in
                    Button(String(format: "%g", value)) { store.jogDistance = value }
                }
            }.disabled(store.busy)
            HStack {
                Button(L("↓ 靠近限位")) { store.jog("toward") }
                Spacer()
                Button(L("↑ 远离限位")) { store.jog("away") }
            }.disabled(!store.canMove)
            HStack {
                uiText("相对原点")
                Spacer()
                uiText((store.status["positionFromHomeMm"] as? Double).map { String(format: "%.2f mm", $0) } ?? "—")
                    .monospacedDigit()
            }
            HStack {
                uiText("下限位")
                Spacer()
                uiText(store.connected ? store.limitPressed ? "已触发" : "已松开" : "—").foregroundStyle(
                    store.limitPressed ? Color.orange : Color.secondary)
            }
            DisclosureGroup(L("原点设置")) {
                VStack(alignment: .leading, spacing: 10) {
                    Button(L("将当前位置设为原点")) { store.saveHome("current") }.disabled(
                        !store.canMove || (store.status["position"] as? Double ?? 0) < 10)
                    Button(L("恢复默认原点")) { store.saveHome("reset") }.disabled(
                        !store.connected || !store.compatible || store.busy
                            || store.status["homePositionSaved"] as? Bool != true)
                    Button(L("重新校准下限位")) { store.motion(.reference) }.disabled(
                        !store.connected || !store.compatible || store.busy || store.limitPressed)
                    uiText("向上为正。位置按丝杆参数估算；设置原点不会移动设备。").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            if store.connected && !store.compatible {
                uiText("设备配置与下限位装置不匹配，移动控制已停用。").foregroundStyle(.orange).font(.caption)
            }
            if let error = store.status["error"] as? String, !error.isEmpty {
                uiText(error).foregroundStyle(.orange).font(.caption)
            }
        }
    }
}
