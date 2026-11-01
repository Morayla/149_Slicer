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
    var body: some View {
        HStack {
            uiText(label).frame(maxWidth: .infinity, alignment: .leading)
            TextField(L(""), text: model.binding(key)).multilineTextAlignment(.trailing).monospacedDigit().frame(
                width: 82
            ).textFieldStyle(.roundedBorder)
            uiText(unit).interfaceFont(.caption).foregroundColor(.secondary).frame(width: 38, alignment: .leading)
        }.frame(minHeight: 30)
    }
}
