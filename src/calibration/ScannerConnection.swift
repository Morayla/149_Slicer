import Foundation

struct ScannerConnection: Codable {
    var host = ""
    var token = ""

    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/149/scanner-connection.json")

    static func load() -> Self {
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return saved
    }

    var isValid: Bool { host.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil && token.count >= 32 }

    func save() throws {
        guard isValid else {
            throw calibrationError(L("请输入有效的设备地址和连接密钥。"))
        }
        try FileManager.default.createDirectory(
            at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }
}
