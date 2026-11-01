import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var model = Workbench()
    @State private var dropTargeted = false
    @State private var details = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var timeline = PathTimeline()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(
                    nsImage: NSImage(
                        contentsOf: Bundle.main.url(forResource: "Logo149VectorWhite", withExtension: "pdf")!)!
                )
                .renderingMode(.template).resizable().scaledToFit().foregroundStyle(.primary)
                .frame(width: 68, height: 44).padding(.horizontal, 12).frame(height: 60).glassCard().accessibilityLabel(
                    L("149 标志"))
                HStack(spacing: 12) {
                    Spacer()
                    Button(action: model.generate) {
                        Label(L(model.busy ? "切片中…" : "切片"), systemImage: "square.3.layers.3d")
                    }
                    .buttonStyle(.borderedProminent).tint(.gray).disabled(!model.canSlice).keyboardShortcut(
                        "r", modifiers: .command)
                    Button(action: model.requestSend) {
                        Label {
                            uiText(model.sendTitle)
                        } icon: {
                            Image(nsImage: FabricationSymbol.image)
                        }
                    }
                    .disabled(!model.canSend)
                }.padding(.horizontal, 16).frame(height: 60).glassCard()
            }.padding(.horizontal, 10).padding(.top, 10)
            if let error = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    uiText(L(error)).font(.callout).lineLimit(3).textSelection(.enabled).help(L(error))
                    Spacer(minLength: 8)
                    Button {
                        model.error = nil
                    } label: {
                        Image(systemName: "xmark")
                    }.buttonStyle(.plain).help(L("收起提示"))
                }.padding(12).background(Color.orange.opacity(0.1))
            }
            HStack(spacing: 0) {
                ParameterPane(model: model).toggleStyle(CapsuleSwitchStyle()).frame(width: 350).glassCard().padding(10)
                previewWorkspace.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity).glassCard().padding(
                    .vertical, 10
                ).padding(.trailing, 10)
            }
        }
        .interfaceFont(.body)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                DeviceToolbarButtons(model: model).labelStyle(.iconOnly)
            }
        }
        .labelStyle(.titleAndIcon)
        .sheet(isPresented: $model.showSendSheet) { GingerPrintSheet(model: model) }
        .focusedSceneObject(model)
        .onAppear { model.scheduleModelPreview(immediate: true) }
        .onChange(of: model.preview?.sha256) { _ in if let p = model.preview { timeline.load(p) } }
        .onChange(of: model.fields) { _ in
            if !model.busy { model.error = nil }
            model.persistDraft()
            model.scheduleModelPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.flushDraft()
        }
        .onChange(of: scenePhase) { phase in if phase != .active { timeline.playing = false } }
        .background(WindowGlass()).frame(minWidth: 980, minHeight: 680)
    }
    private var previewWorkspace: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                NeutralSegments(
                    titles: ["模型", "切片结果"], values: [true, false], selection: $model.showingModel,
                    disabledValues: model.preview == nil ? [false] : []
                ).frame(width: 165)
                Spacer(minLength: 4)
                if model.modelRefreshing { ProgressView().controlSize(.small).help(L("正在更新预览")) }
                if !model.showingModel && model.dirty {
                    Label(L("需重新切片"), systemImage: "circle.fill").font(.caption).foregroundStyle(.orange)
                }
                if !model.showingModel { displayMenu }
                Menu {
                    Button(L("立体视角")) { model.cameraAction(5) }
                    Button(L("俯视")) { model.cameraAction(1) }
                    Button(L("正视")) { model.cameraAction(3) }
                    Button(L("左视")) { model.cameraAction(4) }
                    Divider()
                    Toggle(L("平移模式"), isOn: $model.panMode)
                    Button(L("复位")) { model.cameraAction(0) }
                    Button(L("适合窗口")) { model.cameraAction(2) }
                    if !model.showingModel {
                        Button(L("查看整个平台")) {
                            model.showBed = true
                            model.cameraAction(6)
                        }
                    }
                } label: {
                    Label(L("视角"), systemImage: "rotate.3d")
                }.fixedSize()
            }.controlSize(.small)
            ZStack(alignment: .top) {
                Color(nsColor: .underPageBackgroundColor)
                if model.showingModel, let geometry = model.modelGeometry {
                    ModelPreview(
                        model: geometry, viewAction: model.beadViewAction, zoom: $model.previewZoom,
                        panMode: model.panMode, source: model.fields["SourceMode"] ?? ""
                    )
                    .opacity(model.modelNeedsUpdate ? 0.35 : 1)
                } else if !model.showingModel, let preview = model.preview {
                    ZStack {
                        Color(white: 0.063)
                        BeadPreview(
                            data: preview, zLimit: Double.greatestFiniteMagnitude, showTravel: model.showTravel,
                            showBed: model.showBed, mode: model.previewMode, viewAction: model.beadViewAction,
                            zoom: $model.previewZoom, visibleCount: timeline.cursor.end,
                            segmentFraction: timeline.cursor.fraction,
                            nozzlePoint: timeline.showNozzle ? timeline.cursor.point : nil, asLines: !model.showBeads,
                            panMode: model.panMode)
                    }.opacity(model.dirty ? 0.5 : 1)
                }
                if model.modelGeometry == nil && model.modelError == nil {
                    ProgressView(L("正在准备预览…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error = model.modelError {
                    Label(L(error), systemImage: "exclamationmark.circle").font(.callout).lineLimit(3).textSelection(
                        .enabled
                    ).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(12)
                }
                if model.busy {
                    ProgressView(L("正在切片…")).padding(20).background(
                        .regularMaterial, in: RoundedRectangle(cornerRadius: 12)
                    ).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(dropTargeted ? Color.accentColor : .clear, lineWidth: 2))
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { model.receiveModelDrop($0) }
            if model.showingModel, let geometry = model.modelGeometry {
                HStack {
                    Label(
                        String(
                            format: "%.1f × %.1f × %.1f mm", geometry.dimensions[0], geometry.dimensions[1],
                            geometry.dimensions[2]), systemImage: "ruler"
                    ).monospacedDigit()
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary).opacity(model.modelNeedsUpdate ? 0.5 : 1)
            }
            if !model.showingModel, let preview = model.preview { sliceDetails(preview) }
        }.padding(14)
    }
    private var displayMenu: some View {
        Menu {
            PreviewDisplayMenuItems(model: model)
        } label: {
            Label(L("显示"), systemImage: "eye")
        }.fixedSize()
    }
    private func sliceDetails(_ preview: PreviewResult) -> some View {
        VStack(spacing: 8) {
            PlaybackControls(timeline: timeline, enabled: !model.busy && !model.dirty)
            HStack(spacing: 18) {
                Label(String(format: "%.1f g", preview.summary.mass_g), systemImage: "scalemass")
                Label(String(format: "%.0f min", ceil(preview.summary.motion_minutes)), systemImage: "clock")
                    .help(L("不含预热、调平和加减速影响"))
                if let d = preview.summary.model_dimensions_mm, d.count == 3 {
                    uiText(String(format: "%.1f × %.1f × %.1f mm", d[0], d[1], d[2])).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    details.toggle()
                } label: {
                    Label(L("详情"), systemImage: details ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain)
            }.font(.callout).monospacedDigit().opacity(model.dirty ? 0.5 : 1)
            if model.previewMode != .role && model.previewMode != .xray {
                if model.previewMode == .height {
                    LayerHeightLegend(data: preview)
                } else {
                    MetricLegend(mode: model.previewMode, limits: preview.limits(model.previewMode, model.showTravel))
                }
            }
            if details {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        PrintStatistics(summary: preview.summary)
                        uiText(preview.info).font(.caption).textSelection(.enabled)
                        uiText(model.previewMode.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxHeight: 180)
            }
        }
    }
}
