import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ParameterPane: View {

    @ObservedObject var model: Workbench
    @State private var notes: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeutralSegments(titles: ["打印", "形态"], values: [3, 0], selection: $model.parameterTab)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.parameterTab == 0 {
                        ShapeControls(model: model)
                        Divider()
                        BottomControls(model: model)
                        if model.supportsEffects || model.hasActiveEffects {
                            Divider()
                            uiText("修饰").interfaceFont(.headline)
                            WaveControls(model: model)
                        }
                    } else {
                        PrinterSelector(model: model)
                        Divider()
                        MaterialRecipeSelector(model: model)
                        Divider()
                        PrintProcessControls(model: model)

                    }
                    if !notes.isEmpty {
                        DisclosureGroup(L("说明")) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(notes, id: \.self) { uiText($0) }
                            }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 6)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
                    .environment(\.collectParameterHelp, true)
                    .onPreferenceChange(ParameterHelpPreference.self) {
                        notes = $0.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                    }
            }

        }.padding(16).frame(maxWidth: .infinity).disabled(model.busy)
    }

}
