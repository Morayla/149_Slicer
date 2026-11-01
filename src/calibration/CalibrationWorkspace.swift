import Charts
import SwiftUI

struct CalibrationWorkspace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: CalibrationStore
    var body: some View {
        VStack(spacing: 10) {
            toolbar
            HStack(spacing: 10) {
                if store.sidebarVisible && !store.presentation {
                    parameters.frame(width: 260).glassCard().transition(panelTransition(.leading))
                }
                stage.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity).glassCard()
                if store.resultsVisible { results.frame(width: 280).glassCard().transition(panelTransition(.trailing)) }
            }
            if !store.error.isEmpty || !store.message.isEmpty {
                HStack {
                    uiText(store.error.isEmpty ? store.message : store.error).font(.callout).foregroundStyle(
                        store.error.isEmpty ? Color.secondary : Color.orange
                    ).textSelection(.enabled)
                    Spacer()
                    Button {
                        store.error = ""
                        store.message = ""
                    } label: {
                        Image(systemName: "xmark")
                    }.buttonStyle(.plain).help(L("收起提示"))
                }.padding(.horizontal, 12)
            }
        }.padding(10)
            .onAppear { store.setActive(true) }

            .onDisappear { store.setActive(false) }
            .onExitCommand { if store.busy && store.connected { store.stop() } else { store.presentation = false } }
            .onChange(of: store.displayKey) { _ in store.persistDisplay() }

            .alert(L("替换当前测量记录？"), isPresented: $store.showDiscard) {
                Button(L("取消"), role: .cancel) {}
                Button(L("替换"), role: .destructive) { store.confirmReplace() }
            } message: {
                uiText("当前记录将从工作区清空，请先保存需要保留的数据。")
            }
            .sheet(isPresented: $store.showDraft) { draftSheet }
            .sheet(isPresented: $store.showCalibration) { GaugeCalibrationSheet(store: store) }
            .sheet(isPresented: $store.showCamera) {
                VStack {
                    HStack {
                        uiText("相机实时画面").font(.headline)
                        Spacer()
                        Button(L("停止"), role: .destructive) { store.stop() }
                        Button(L("关闭")) { store.showCamera = false }
                    }
                    CalibrationCameraView(store: store).frame(minWidth: 640, minHeight: 400)
                }.padding(20)
            }
    }
    private func panelTransition(_ edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
    private func animatePanels(_ change: () -> Void) {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.10 : 0.24), change)
    }
    private var toolbar: some View {
        HStack {
            Button {
                animatePanels {
                    if store.presentation { store.resultsVisible.toggle() } else { store.sidebarVisible.toggle() }
                }
            } label: {
                Label(L(store.presentation ? "测量结果" : "参数"), systemImage: "sidebar.left")
            }.help(L("显示或隐藏侧栏"))
            Spacer()
            Button {
                animatePanels { store.presentation.toggle() }
            } label: {
                Label(
                    L(store.presentation ? "返回工作区" : "演示视图"),
                    systemImage: store.presentation
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            Button {
                animatePanels { store.resultsVisible.toggle() }
            } label: {
                Label(L("测量结果"), systemImage: "sidebar.right")
            }
        }.buttonStyle(.borderless).controlSize(.small).padding(.horizontal, 6)
    }
    private var parameters: some View {
        VStack(spacing: 10) {
            NeutralSegments(
                titles: CalibrationStore.Workspace.allCases.map(\.rawValue),
                values: CalibrationStore.Workspace.allCases, selection: $store.workspace,
                disabledValues: store.busy ? [.simulation] : []
            ).padding([.horizontal, .top], 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.workspace == .device { CalibrationDeviceControls(store: store) } else { specimenControls }
                }.padding(14)
            }
        }
    }
    private var specimenControls: some View {
        Group {
            uiText("样件").font(.headline)
            CalibrationNumberRow("样件高度", value: $store.config.height, unit: "mm")
            CalibrationNumberRow("打印层高", value: $store.config.step, unit: "mm")
            CalibrationNumberRow("打印线宽", value: $store.config.lineWidth, unit: "mm")
            CalibrationNumberRow("外径", value: $store.config.diameter, unit: "mm")
            Divider()
            uiText("测量范围").font(.headline)
            HStack {
                uiText("从顶部测量")
                Spacer()
                TextField(L("层数"), value: $store.config.scanLayers, format: .number).frame(width: 64)
                    .multilineTextAlignment(.trailing)
                uiText("层").foregroundStyle(.secondary)
            }
            CalibrationNumberRow("偏差阈值", value: $store.config.tolerance, unit: "mm")
            uiText("样件倒置，原始打印第 1 层朝上。").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(L("演示与运动参数")) {
                VStack(spacing: 12) {
                    CalibrationNumberRow("象脚外扩", value: $store.config.foot, unit: "mm")
                    CalibrationNumberRow("衰减高度", value: $store.config.decay, unit: "mm")
                    CalibrationNumberRow("下降速度", value: $store.config.speed, unit: "mm/s")
                    CalibrationNumberRow("停稳时间", value: $store.config.dwell, unit: "s")
                }.padding(.top, 10)
            }
            Button(L("更新测量任务")) { store.applyConfig() }.frame(maxWidth: .infinity)
        }
    }
    private var stage: some View {
        VStack(spacing: 0) {
            HStack {
                uiText(store.workspace == .device ? "测量装置" : "样件演示").font(.headline)
                Spacer()
                Menu {
                    SelectionMenuItems(
                        options: [("iso", "等距"), ("front", "正视"), ("side", "侧视"), ("top", "俯视")],
                        selection: $store.cameraView)
                } label: {
                    Image(systemName: "rotate.3d")
                }.menuStyle(.borderlessButton).fixedSize().help(L("视角")).accessibilityLabel(L("视角"))
                Menu {
                    SelectionMenuItems(
                        options: [("clay", "素模"), ("lines", "线稿"), ("xray", "X 光")], selection: $store.sceneMode)
                    Toggle(L("X 光白底"), isOn: $store.xrayWhite)
                    Divider()
                    Toggle(L("电子组件"), isOn: $store.electronicsVisible)
                    Toggle(L("线缆"), isOn: $store.wiresVisible)
                    Toggle(L("打开电气盒"), isOn: $store.electronicsOpen)
                    Divider()
                    Slider(value: $store.grain, in: 0...0.2) { uiText("表面颗粒") }
                    Slider(value: $store.lineStrength, in: 0.15...1) { uiText("线条亮度") }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }.menuStyle(.borderlessButton).fixedSize().help(L("显示设置")).accessibilityLabel(L("显示设置"))
                Button {
                    store.renderer.zoom(1 / 1.15)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }.help(L("缩小"))
                Button {
                    store.renderer.fit(store.cameraView)
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }.help(L("适配")).accessibilityLabel(L("适配模型"))
                Button {
                    store.renderer.zoom(1.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }.help(L("放大"))
            }.buttonStyle(.borderless).padding(14)
            ZStack {
                NativeCalibrationScene(store: store)
                if store.loading { ProgressView(L("正在加载装置…")) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel(L("三维校准装置，可拖动旋转和缩放"))
            transport.padding(14)
        }
    }
    private var transport: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.workspace == .device {
                ProgressView(value: Double(store.deviceRows.count), total: Double(max(1, store.deviceTotal)))
                HStack {
                    Button(L(store.scanDirection == "away" ? "开始扫描 ↑" : "开始扫描 ↓")) { store.startDeviceScan() }.disabled(
                        !store.canScan)
                    Button(L("停止"), role: .destructive) { store.stop() }.disabled(!store.connected)
                    Spacer()
                    uiText("\(store.deviceRows.count) / \(store.deviceTotal)").monospacedDigit()
                }
                uiText(store.scanGate).foregroundStyle(.secondary).font(.caption)
            } else {
                ProgressView(value: Double(store.rows.count), total: Double(max(1, store.simulation.config.plan.count)))
                HStack {
                    Button(
                        L(
                            store.simulation.running
                                ? "暂停" : store.simulation.paused && store.simulation.phase != .done ? "继续" : "开始演示 ↓")
                    ) { store.toggleSimulation() }.disabled(!store.simulation.config.reachable)
                    Button(L("重置")) { store.reset() }
                    Spacer()
                    uiText("\(store.rows.count) / \(store.simulation.config.plan.count)").monospacedDigit()
                }
                HStack {
                    uiText(store.simulationPhase)
                    Spacer()
                    uiText(String(format: "Z %.1f mm", store.currentHeight)).monospacedDigit()
                }.foregroundStyle(.secondary).font(.caption)
                if !store.simulation.config.reachable {
                    uiText("测量范围超出装置行程，请调整样件高度或测量层数。").foregroundStyle(.orange).font(.caption)
                }
            }
        }
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                uiText("测量结果").font(.headline)
                Spacer()
                Button {
                    store.exportCSV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }.buttonStyle(.borderless).help(L("导出 CSV"))
            }
            if store.workspace == .device { deviceResults } else { simulationResults }
        }.padding(14)
    }
    private var simulationResults: some View {
        Group {
            HStack(alignment: .firstTextBaseline) {
                uiText(store.currentError.map { String(format: "%+.3f", $0) } ?? "—").font(
                    .system(size: 32, weight: .medium, design: .rounded)
                ).monospacedDigit()
                uiText("mm").foregroundStyle(.secondary)
            }
            HStack {
                uiText(LF("第 %@ 层", String(store.currentLayer))).foregroundStyle(.secondary)
                Spacer()
                if store.selectedLayer != nil { Button(L("跟随扫描")) { store.selectedLayer = nil }.buttonStyle(.link) }
            }
            CalibrationProfile(config: store.simulation.config, rows: store.rows, selected: store.currentLayer).frame(
                height: 160)
            deviationChart
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.rows.sorted { $0.layer < $1.layer }) { row in
                        HStack {
                            Toggle(
                                LF("采用第 %@ 层", String(row.layer)),
                                isOn: Binding(
                                    get: { !store.excluded.contains(row.layer) },
                                    set: { _ in store.toggleExcluded(row.layer) })
                            ).labelsHidden().toggleStyle(.checkbox)
                            Button {
                                store.selectedLayer = row.layer
                            } label: {
                                HStack {
                                    uiText(String(format: "%02d", row.layer))
                                    Spacer()
                                    uiText(String(format: "%+.3f mm", row.radialErrorMm)).monospacedDigit()
                                    if abs(row.radialErrorMm) > store.simulation.config.tolerance {
                                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                    }
                                }.padding(6).background(
                                    store.currentLayer == row.layer ? Color.primary.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            CalibrationNumberRow("墙体起始高度", value: $store.baseHeight, unit: "mm")
            Button(L("检查补偿方案")) { store.reviewDraft() }.disabled(store.rows.isEmpty).frame(maxWidth: .infinity)
            uiText(store.recordMode == "simulation" ? "模拟数据 · 不代表实测结果" : "原始测量记录").font(.caption).foregroundStyle(
                .secondary)
        }
    }
    private var deviationChart: some View {
        Chart {
            ForEach(store.rows.sorted { $0.layer < $1.layer }) { row in
                LineMark(x: .value("偏差", row.radialErrorMm), y: .value("层", row.layer)).foregroundStyle(Color.secondary)
                PointMark(x: .value("偏差", row.radialErrorMm), y: .value("层", row.layer)).foregroundStyle(
                    store.excluded.contains(row.layer)
                        ? Color.secondary.opacity(0.3)
                        : abs(row.radialErrorMm) > store.simulation.config.tolerance ? Color.orange : Color.primary)
            }
            RuleMark(x: .value("零", 0)).foregroundStyle(Color.secondary.opacity(0.4))
            RuleMark(x: .value("阈值", store.simulation.config.tolerance)).foregroundStyle(Color.orange.opacity(0.4))
                .lineStyle(StrokeStyle(dash: [3, 3]))
        }.chartYScale(domain: .automatic(reversed: true)).frame(height: 130)
    }
    private var deviceResults: some View {
        Group {
            uiText(
                store.deviceRows.last?["deltaMm"].flatMap { $0 as? Double }.map {
                    abs($0) <= store.smallThreshold ? "≈ 0" : String(format: "%+.3f", $0)
                } ?? "—"
            ).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            uiText("相对首点变化 · mm").font(.caption).foregroundStyle(.secondary)
            CalibrationNumberRow("显示阈值", value: $store.smallThreshold, unit: "mm")
            CalibrationProfile(config: store.simulation.config, rows: [], selected: nil).frame(height: 160)
            uiText("单侧测点仅表示局部变化，轮廓显示名义尺寸。").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.deviceRows.enumerated()), id: \.offset) { index, row in
                        HStack {
                            uiText(String(format: "%02d", row["point"] as? Int ?? index + 1))
                            Spacer()
                            uiText(String(format: "%.1f mm", row["offsetMm"] as? Double ?? 0)).foregroundStyle(
                                .secondary)
                            Spacer()
                            uiText(String(format: "%+.4f", row["deltaMm"] as? Double ?? 0)).monospacedDigit()
                        }
                    }
                }
            }
            Button(L("清除设备记录")) { store.clearDeviceScan() }.disabled(
                store.busy || !store.connected || store.deviceRows.isEmpty)
        }
    }
    private var draftSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            uiText("检查补偿方案").font(.title2)
            if let draft = store.draft {
                uiText(draft.simulated ? "此方案包含模拟数据" : "此方案来自实测记录").foregroundStyle(
                    draft.simulated ? Color.orange : Color.secondary)
                HStack {
                    uiText(String(format: L("补偿量 %.3f mm"), draft.amount))
                    Spacer()
                    uiText(LF("%@ 圈", String(draft.turns)))
                }
                uiText(String(format: L("末端基准 %.3f mm · 采用 %d 层"), draft.baseline, draft.usedLayers)).foregroundStyle(
                    .secondary)
                ScrollView {
                    uiText(draft.table).font(.system(.body, design: .monospaced)).frame(
                        maxWidth: .infinity, alignment: .leading
                    ).textSelection(.enabled)
                }.frame(height: 180)
                uiText("原始读数保持不变。方案按末端基准和单调拟合计算；导出后可在切片软件的补偿预设中导入。").foregroundStyle(.secondary).font(.callout)
            }
            if !store.error.isEmpty { uiText(store.error).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button(L("取消")) { store.showDraft = false }
                Button(L("导出补偿预设…")) { store.exportDraft() }.disabled(store.draft == nil)
            }
        }.padding(24).frame(width: 460)
    }
}
struct CalibrationNumberRow: View {
    let title: String
    @Binding var value: Double
    var unit: String
    init(_ title: String, value: Binding<Double>, unit: String = "") {
        self.title = title
        _value = value
        self.unit = unit
    }
    var body: some View {
        HStack(spacing: 8) {
            uiText(title).lineLimit(2)
            Spacer(minLength: 4)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...3))).multilineTextAlignment(
                .trailing
            ).frame(width: 65)
            uiText(unit).foregroundStyle(.secondary).font(.caption).frame(width: 32, alignment: .leading)
        }
    }
}
