import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProjectCommands: Commands {
    @FocusedObject private var model: Workbench?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("打开项目…")) { model?.openProject() }.keyboardShortcut("o").disabled(
                model == nil || model?.busy == true)
            Button(L("保存项目")) { _ = model?.saveProject() }.keyboardShortcut("s").disabled(
                model == nil || model?.busy == true)
            Button(L("另存为…")) { _ = model?.saveProject(asNew: true) }.keyboardShortcut(
                "s", modifiers: [.command, .shift]
            )
            .disabled(model == nil || model?.busy == true)
            Divider()

            Button(L("导出 G-code…")) { model?.exportGcode() }.keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model == nil || model?.busy == true || model?.dirty != false || model?.preview == nil)
        }
    }
}
