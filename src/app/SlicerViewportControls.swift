import SwiftUI

struct SlicerViewportControls: View {
    @ObservedObject var model: Workbench
    @State private var menu: ViewportMenu?
    var body: some View {
        ViewportMenus(white: $model.backgroundWhite, menu: $menu, scope: "slicer") {
            displayOptions
        } camera: {
            cameraOptions
        }.onChange(of: model.showingModel) { _ in menu = nil }
    }
    @ViewBuilder private var displayOptions: some View {
        if model.showingModel {
            ViewportMenuRow(title: "白模", selected: model.modelShading == "solid", selection: .single) { model.modelShading = "solid" }
            ViewportMenuRow(title: "材质", selected: model.modelShading == "rendered", selection: .single) { model.modelShading = "rendered" }
        } else {
            ForEach(PreviewMode.allCases.filter { $0 != .xray }) { mode in
                ViewportMenuRow(title: mode.rawValue, selected: model.previewMode == mode, selection: .single) { model.previewMode = mode }
            }
            Divider().padding(.vertical, 3)
            ViewportMenuRow(title: "显示线宽", selected: model.showBeads) { model.showBeads.toggle() }
            ViewportMenuRow(title: "空移路径", selected: model.showTravel) { model.showTravel.toggle() }
            ViewportMenuRow(title: "喷嘴", selected: model.showNozzle) { model.showNozzle.toggle() }
        }
        Divider().padding(.vertical, 3)
        ViewportMenuRow(title: "打印平台", selected: model.showBed) { model.showBed.toggle() }
    }
    @ViewBuilder private var cameraOptions: some View {
        ForEach([(5, "等距"), (3, "正视"), (4, "侧视"), (1, "俯视")], id: \.0) { value, title in
            ViewportMenuRow(title: title, selected: model.cameraOrientation == value, selection: .single) {
                model.cameraAction(value); menu = nil
            }
        }
        Divider().padding(.vertical, 3)
        ViewportMenuRow(title: "适合窗口", selection: .action) { model.cameraAction(2); menu = nil }
    }
}

struct ViewportStageSwitch: View {
    @ObservedObject var model: Workbench
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 2) {
            stage("形态", modelView: true)
            stage("切片", modelView: false)
        }.padding(3).background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.12), lineWidth: 0.5))
            .environment(\.colorScheme, model.backgroundWhite ? .light : .dark)
            .padding(10)
    }
    private func stage(_ title: String, modelView: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.showingModel = modelView }
        } label: {
            uiText(title).padding(.horizontal, 15).padding(.vertical, 6)
                .background {
                    if model.showingModel == modelView {
                        Capsule().fill(.primary.opacity(0.13)).matchedGeometryEffect(id: "selected", in: selection)
                    }
                }.contentShape(Capsule())
        }.buttonStyle(.plain)
            .help(L(title))
            .accessibilityIdentifier(modelView ? "slicer.stage.shape" : "slicer.stage.slice")
    }
}
