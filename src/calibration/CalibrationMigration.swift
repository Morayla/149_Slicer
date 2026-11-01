import Foundation
import SQLite3

// Read only calibration-owned keys from the previous WebKit store. The old store remains intact.
enum CalibrationMigration {
    static func read(bundleIdentifier: String) -> [String: String] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/WebKit/\(bundleIdentifier)/WebsiteData")
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [:] }
        let files = enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent == "localstorage.sqlite3" || $0.pathExtension == "localstorage"
        }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast)
        }
        let keys = [
            "149-calibration-session", "149-calibration-view", "149-calibration-xray-background",
            "149-calibration-camera", "149-calibration-line-contrast", "149-calibration-sidebar", "149-travel-speed",
            "149-small-change-threshold",
        ]
        for file in files {
            var database: OpaquePointer?
            guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
            else {
                if let database = database { sqlite3_close(database) }
                continue
            }
            defer { sqlite3_close(database) }
            sqlite3_busy_timeout(database, 50)
            var values: [String: String] = [:]
            for key in keys {
                var statement: OpaquePointer?
                guard
                    sqlite3_prepare_v2(
                        database, "SELECT value FROM ItemTable WHERE key=?1 LIMIT 1", -1, &statement, nil) == SQLITE_OK
                else { continue }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else {
                    continue
                }
                let count = Int(sqlite3_column_bytes(statement, 0))
                guard count > 0, count < 10_000_000 else { continue }
                let data = Data(bytes: pointer, count: count)
                if let value = String(data: data, encoding: .utf16LittleEndian) { values[key] = value }
            }
            if let text = values["149-calibration-session"], let data = text.data(using: .utf8),
                (try? CalibrationRecord.decode(data)) != nil
            {
                return values
            }
        }
        return [:]
    }
}
