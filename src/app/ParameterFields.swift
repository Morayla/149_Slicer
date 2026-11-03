import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct NumberRow: View {

    @ObservedObject var model: Workbench
    let label: String
    let key: String
    var unit: String = "mm"
    private var rule: ShapeParameterRule? { ShapeParameterRules.rule(key) }
    private var isIntegral: Bool {
        (rule?.integer ?? false) || ["层", "点", "轮", "个", "件"].contains(unit) || ["N", "TriplePts", "B"].contains(key)
    }
    private var dragStep: Double {
        if isIntegral || ["°", "%", "℃", "°C"].contains(unit) { return 1 }
        if unit == "×" { return 0.01 }
        if ["g/cm³", "kg/L"].contains(unit) { return 0.001 }
        return 0.1
    }
    var body: some View {
        HStack {
            uiText(label).frame(maxWidth: .infinity, alignment: .leading)
            NumericField(
                label, text: model.binding(key), step: dragStep, integral: isIntegral, minimum: rule?.minimum,
                maximum: rule?.maximum
            ).frame(
                width: ParameterLayout.valueWidth
            )
            uiText(unit).interfaceFont(.caption).foregroundColor(.secondary).frame(
                width: WorkspaceLayout.unitWidth, alignment: .leading)
        }.frame(minHeight: WorkspaceLayout.rowHeight)
    }
}
