import AppKit
import CoreFoundation
import Foundation
import SwiftUI

struct ContentView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var model = Workbench()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sliceReady = false
    @State private var timeline = PathTimeline()
    private let pauseWhenInactive: Bool
    init(viewModel: Workbench? = nil, timeline: PathTimeline? = nil, pauseWhenInactive: Bool = true) {
        _model = StateObject(wrappedValue: viewModel ?? Workbench())
        _timeline = State(wrappedValue: timeline ?? PathTimeline())
        self.pauseWhenInactive = pauseWhenInactive
    }
    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader {
                Button(action: model.generate) {
                    Label(L(model.busy ? "切片中…" : "切片"), systemImage: "square.3.layers.3d")
                }
                .buttonStyle(.borderedProminent).tint(.gray).disabled(!model.canSlice)
                .keyboardShortcut("r", modifiers: .command)
                Button(action: model.requestSend) {
                    Label {
                        uiText(model.sendTitle)
                    } icon: {
                        Image(nsImage: FabricationSymbol.image)
                    }
                }.disabled(!model.canSend)
            }
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
            HStack(spacing: 10) {
                if model.parametersVisible {
                    ParameterPane(model: model).toggleStyle(CapsuleSwitchStyle())
                        .frame(width: WorkspaceLayout.sidebarWidth).glassCard()
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
                previewWorkspace.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity).glassCard()
            }.padding(10)
                .animation(.easeInOut(duration: reduceMotion ? 0.10 : 0.24), value: model.parametersVisible)
        }
        .environment(\.numericScrubChanged, model.setInteractivePreview)
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
        .onChange(of: model.preview?.sha256) { _ in
            sliceReady = false
            if let p = model.preview { timeline.load(p) }
        }
        .onChange(of: model.fields["SourceMode"]) { _ in
            model.finishPlacement()
            model.cameraAction(0)
        }
        .onChange(of: model.showingModel) { if !$0 { model.finishPlacement() } }
        .onChange(of: model.fields) { _ in
            if !model.busy { model.error = nil }
            model.persistDraft()
            if model.placementTool != .move { model.scheduleModelPreview() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.flushDraft()
        }
        .onChange(of: scenePhase) { phase in if pauseWhenInactive && phase != .active { timeline.playing = false } }
        .background(WindowGlass()).frame(minWidth: 980, minHeight: 680)
    }
    private func toggleParameters() {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.10 : 0.24)) { model.parametersVisible.toggle() }
    }
    private var previewWorkspace: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                Color(white: model.backgroundWhite ? 0.94 : 0.063)
                if let geometry = model.modelGeometry {
                    ModelPreview(
                        model: geometry, viewAction: model.beadViewAction, zoom: $model.previewZoom,
                        panMode: model.panMode, source: model.fields["SourceMode"] ?? "", shading: model.modelShading,
                        appearance: model.materialAppearance, backgroundWhite: model.backgroundWhite,
                        sharedCamera: model.sharedCamera, outlineStrength: 0, xray: false, fields: model.fields,
                        active: model.showingModel || !sliceReady, xrayStrength: model.lineStrength, placement: model,
                        showBed: model.showBed, bedSize: model.printerBedSize
                    ).opacity(model.showingModel || !sliceReady ? 1 : 0).allowsHitTesting(model.showingModel)
                        .animation(nil, value: model.showingModel)
                }
                if let preview = model.preview {
                    ZStack {
                        Color(white: model.backgroundWhite ? 0.94 : 0.063)
                        SlicePlaybackPreview(model: model, timeline: timeline, data: preview) { sliceReady = true }
                    }.opacity(!model.showingModel && sliceReady ? (model.dirty ? 0.5 : 1) : 0)
                        .allowsHitTesting(!model.showingModel && sliceReady)
                        .animation(nil, value: model.showingModel)
                }
                if model.modelGeometry == nil && model.modelError == nil {
                    ProgressView(L("正在准备预览…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error = model.modelError {
                    Label(L(error), systemImage: "exclamationmark.circle").font(.callout).lineLimit(3).textSelection(
                        .enabled
                    ).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 12).padding(.bottom, model.showingModel ? 12 : 64)
                }
                if model.busy {
                    ProgressView(L("正在切片…")).padding(20).background(
                        .regularMaterial, in: RoundedRectangle(cornerRadius: 12)
                    ).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !model.showingModel && !model.busy && (model.dirty || model.preview == nil) {
                    VStack(spacing: 12) {
                        uiText(model.preview == nil ? "切片后查看打印路径" : "形态已更改，请重新切片。")
                        Button(L(model.preview == nil ? "切片" : "重新切片"), action: model.generate)
                            .buttonStyle(.borderedProminent).tint(.gray).disabled(!model.canSlice)
                    }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .top) { ViewportStageSwitch(model: model) }
            .overlay(alignment: .topLeading) {
                if !model.showingModel, !model.dirty, let preview = model.preview {
                    SliceLegend(
                        data: preview, mode: model.previewMode, showTravel: model.showTravel,
                        white: model.backgroundWhite
                    ).padding(10)
                } else if model.showingModel {
                    PlacementToolbar(model: model).padding(10)
                }

            }
            .overlay(alignment: .leading) {
                ViewportPanelHandle(
                    scope: "slicer", backgroundWhite: model.backgroundWhite, leading: true,
                    expanded: model.parametersVisible, action: toggleParameters)
            }
            .overlay(alignment: .trailing) {
                if !model.showingModel, !model.dirty, model.preview != nil {
                    LayerOverlay(timeline: timeline).padding(.trailing, 10).padding(.vertical, 64)
                        .environment(\.colorScheme, model.backgroundWhite ? .light : .dark)
                }
            }
            .overlay(alignment: .bottom) {
                if !model.showingModel, !model.dirty, let preview = model.preview {
                    PlaybackOverlay(
                        timeline: timeline, enabled: !model.busy && !model.dirty,
                        mass: preview.summary.mass_g, minutes: preview.summary.motion_minutes
                    )
                    .environment(\.colorScheme, model.backgroundWhite ? .light : .dark)
                    .padding(.horizontal, 54).padding(.bottom, 10)
                }
            }
            .overlay { SlicerViewportControls(model: model) }
        }.padding(10)
    }
}
