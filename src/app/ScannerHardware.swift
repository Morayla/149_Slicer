import Foundation

/// The web view never receives the controller credential.
final class ScannerHardware {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.timeoutIntervalForResource = 5
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration:c)
    }()
    func request(_ body:[String:Any], completion:@escaping([String:Any])->Void) {
        let id = body["id"] as? String ?? ""
        func finish(_ result:[String:Any]) {
            var response=result;response["id"]=id
            DispatchQueue.main.async {completion(response)}
        }
        guard let method=body["method"] as? String,["status","camera","home","reference","jog","stop","needle","calibrate","needle-check","scan","scan-clear","home-position"].contains(method) else {
            finish(["error":"Unknown hardware command"]);return
        }
        let file=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/149/scanner-connection.json")
        guard let data=try? Data(contentsOf:file),let config=(try? JSONSerialization.jsonObject(with:data)) as? [String:String],
              let host=config["host"],host.range(of:"^[A-Za-z0-9.-]+$",options:.regularExpression) != nil,
              let token=config["token"],token.count>=32,
              let url=URL(string:"http://\(host):8765/api/\(method)") else {
            finish(["error":"Scanner connection is not configured on this Mac"]);return
        }
        var request=URLRequest(url:url)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        if ["home","reference","jog","stop","calibrate","needle-check","scan","scan-clear","home-position"].contains(method) {
            request.httpMethod="POST"
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            let params=body["params"] as? [String:Any] ?? [:]
            request.httpBody=try? JSONSerialization.data(withJSONObject:params)
        }
        session.dataTask(with:request){data,response,error in
            if let error=error {finish(["error":error.localizedDescription]);return}
            guard let response=response as? HTTPURLResponse,let data=data else {finish(["error":"No response from scanner"]);return}
            if method=="camera",response.statusCode==200,data.count<2_000_000 {
                finish(["data":["image":"data:image/jpeg;base64,"+data.base64EncodedString()]]);return
            }
            let obj=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
            if !(200...299).contains(response.statusCode) {finish(["error":obj["error"] as? String ?? "Scanner request failed"])}
            else {finish(["data":obj])}
        }.resume()
    }
}
