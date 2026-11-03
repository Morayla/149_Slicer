import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let slicerProject = UTType(exportedAs: "com.149.slicer.project", conformingTo: .json)
}

extension Workbench {
    func documentData() throws -> Data {
        var saved = try project()
        saved["appearance"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(materialAppearance))
        return try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted, .sortedKeys])
    }
    func writeProject(to url: URL) throws {
        let data = try documentData()
        try data.write(to: url, options: .atomic)
        documentURL = url
        savedDocumentData = data
        status = LF("项目已保存：%@", url.lastPathComponent)
    }
    @discardableResult func saveProject(asNew: Bool = false) -> Bool {
        do {
            if !asNew, let url = documentURL, url.pathExtension.lowercased() == "149slicer" {
                try writeProject(to: url)
                return true
            }
            let panel = NSSavePanel()
            panel.title = L(asNew ? "另存项目…" : "保存项目")
            panel.allowedContentTypes = [.slicerProject]
            panel.nameFieldStringValue =
                (documentURL?.deletingPathExtension().lastPathComponent ?? L("149 项目")) + ".149slicer"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            try writeProject(to: url)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func confirmProjectReplacement() -> Bool {
        guard let current = try? documentData(), let savedDocumentData, current != savedDocumentData else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = L("保存当前项目的更改？")
        alert.informativeText = L("打开另一个项目会替换当前参数。")
        alert.addButton(withTitle: L("保存"))
        alert.addButton(withTitle: L("不保存"))
        alert.addButton(withTitle: L("取消"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveProject()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
    func openProject() {
        let panel = NSOpenPanel()
        panel.title = L("打开 149 项目")
        panel.allowedContentTypes = [.slicerProject, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }
    func openProject(at url: URL) {
        guard !busy else {
            error = L("请等待当前切片完成后再打开项目。")
            return
        }
        guard confirmProjectReplacement() else { return }
        do {
            guard let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw message("项目格式无效。")
            }
            try applyProject(raw)
            documentURL = url
            savedDocumentData = try documentData()
            preview = nil
            gcodeURL = nil
            modelGeometry = nil
            showingModel = true
            status = LF("已载入 %@，模型预览会自动更新。", url.lastPathComponent)
            scheduleModelPreview(immediate: true)
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
final class SlicerAppDelegate: MainWindowAppDelegate {
    var receiveProject: ((URL) -> Void)? {
        didSet {
            if let pendingProject, let receiveProject {
                self.pendingProject = nil
                receiveProject(pendingProject)
            }
        }
    }
    private var pendingProject: URL?
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let receiveProject { receiveProject(url) } else { pendingProject = url }
        _ = applicationShouldHandleReopen(application, hasVisibleWindows: false)
    }
}
