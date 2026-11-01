import Foundation

enum ScannerCommand: String {
    case status, camera, home, reference, jog, stop, needle, calibrate, scan
    case needleCheck = "needle-check"
    case scanClear = "scan-clear"
    case homePosition = "home-position"

    var changesDevice: Bool { ![.status, .camera, .needle].contains(self) }
    var requiresSetup: Bool { [.home, .reference, .jog, .scan, .homePosition].contains(self) }
}

final class ScannerHardware {
    private let session: URLSession
    private let connection: () -> ScannerConnection

    init(session: URLSession? = nil, connection: @escaping () -> ScannerConnection = ScannerConnection.load) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config)
        self.connection = connection
    }

    func request(
        _ command: ScannerCommand, params: [String: Any] = [:],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        func finish(_ result: Result<[String: Any], Error>) {
            DispatchQueue.main.async { completion(result) }
        }
        let saved = connection()
        guard saved.isValid, let url = URL(string: "http://\(saved.host):8765/api/\(command.rawValue)") else {
            finish(.failure(calibrationError(L("尚未配置扫描设备连接"))))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "Authorization")
        do {
            if command.changesDevice {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: params)
            }
        } catch {
            finish(.failure(error))
            return
        }
        session.dataTask(with: request) { data, response, error in
            if let error {
                finish(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse, let data else {
                finish(.failure(calibrationError(L("扫描设备未返回有效响应"))))
                return
            }
            do {
                if command == .camera, response.statusCode == 200 {
                    guard !data.isEmpty, data.count < 2_000_000 else { throw calibrationError(L("相机图像无效")) }
                    finish(.success(["imageData": data]))
                } else {
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw calibrationError(L("扫描设备未返回有效响应"))
                    }
                    guard (200...299).contains(response.statusCode) else {
                        throw calibrationError(
                            object["error"] as? String ?? LF("设备请求失败（HTTP %@）", String(response.statusCode)))
                    }
                    finish(.success(object))
                }
            } catch { finish(.failure(error)) }
        }.resume()
    }
}
