import SwiftUI

struct PreviewDisplayMenuItems: View {
    @ObservedObject var model: Workbench

    var body: some View {
        ForEach(PreviewMode.allCases) { mode in
            Toggle(
                L(mode.rawValue),
                isOn: Binding(
                    get: { model.previewMode == mode },
                    set: { if $0 { model.previewMode = mode } }
                ))
        }
        Divider()
        Toggle(L("料道"), isOn: $model.showBeads)
        Toggle(L("空移"), isOn: $model.showTravel)
        Toggle(L("打印平台"), isOn: $model.showBed)
    }
}
