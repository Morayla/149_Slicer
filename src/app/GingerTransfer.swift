import Foundation
import CryptoKit
import SwiftUI

final class NoPrinterRedirect:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {completionHandler(nil)}
}

struct GingerUploadResult {
    let filename:String
    let started:Bool
    let queued:Bool
}

final class GingerClient {
    private let session:URLSession
    init(session:URLSession?=nil) {
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=120
        self.session=session ?? URLSession(configuration:config,delegate:NoPrinterRedirect(),delegateQueue:nil)
    }
    static func failure(_ message:String)->NSError {NSError(domain:"149.Ginger",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    static func candidates(_ address:String)throws->[URL] {
        let url=try PrinterAddress.parse(address)
        var parts=URLComponents(url:url,resolvingAgainstBaseURL:false)!
        parts.query=nil;parts.fragment=nil
        var result=[parts.url!]
        if parts.path != "" && parts.path != "/" {parts.path="";result.append(parts.url!)}
        // Standard Moonraker port on the SAME host only; never downgrade HTTPS.
        if parts.scheme=="http" && (parts.port==nil || parts.port==80) {
            parts.port=7125;parts.path="";result.append(parts.url!)
        }
        return result
    }
    func request(_ base:URL,_ path:String,key:String,method:String="GET")->URLRequest {
        var parts=URLComponents(url:base,resolvingAgainstBaseURL:false)!
        parts.path=parts.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        parts.path="/"+([parts.path,path].filter{!$0.isEmpty}.joined(separator:"/"))
        var r=URLRequest(url:parts.url!);r.httpMethod=method
        if !key.isEmpty {r.setValue(key,forHTTPHeaderField:"X-Api-Key")}
        r.setValue("application/json",forHTTPHeaderField:"Accept")
        return r
    }
    static func decode(_ data:Data,_ response:URLResponse)throws->[String:Any] {
        guard let http=response as? HTTPURLResponse else {throw failure("机器返回了无效响应。")}
        if http.statusCode==401 || http.statusCode==403 {throw NSError(domain:"149.Ginger.Auth",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:"机器要求授权，请填写 Moonraker API Key，或在机器网页中检查访问设置。"])}
        guard (200...299).contains(http.statusCode) else {throw failure("机器返回 HTTP \(http.statusCode)。")}
        guard let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {throw failure("该地址返回的是网页，未找到 Moonraker 接口。")}
        if json["error"] != nil {throw failure("机器接口返回错误，请查看机器网页。")}
        return json["result"] as? [String:Any] ?? json
    }
    func resolve(_ address:String,key:String)async throws->URL {
        for candidate in try Self.candidates(address) {
            do {
                let (data,response)=try await session.data(for:request(candidate,"server/info",key:key))
                let result=try Self.decode(data,response)
                if result["klippy_state"] is String {return candidate}
            } catch {if (error as NSError).domain=="149.Ginger.Auth" {throw error}}
        }
        throw Self.failure("无法连接 Moonraker。请确认同一网络、机器地址和端口；可尝试 IP:7125。")
    }
    func ready(_ base:URL,key:String)async throws {
        var r=request(base,"printer/objects/query",key:key)
        var p=URLComponents(url:r.url!,resolvingAgainstBaseURL:false)!
        p.queryItems=[URLQueryItem(name:"print_stats",value:nil),URLQueryItem(name:"webhooks",value:nil)];r.url=p.url
        let (data,response)=try await session.data(for:r)
        let result=try Self.decode(data,response)
        guard let status=result["status"] as? [String:Any],let hooks=status["webhooks"] as? [String:Any],hooks["state"] as? String=="ready",
              let stats=status["print_stats"] as? [String:Any],let state=stats["state"] as? String else {throw Self.failure("打印机未就绪，请先查看机器网页。")}
        guard ["standby","complete","cancelled","error"].contains(state) else {throw Self.failure("打印机正在打印或暂停，不能启动新的任务。")}
    }
    static func multipart(file:Data,name:String,printNow:Bool,boundary:String)throws->Data {
        guard name.hasSuffix(".gcode"),name.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0))}) else {throw failure("上传文件名无效。")}
        var body=Data()
        func add(_ s:String){body.append(Data(s.utf8))}
        for (field,value) in [("root","gcodes"),("print",printNow ? "true":"false"),("checksum",SHA256.hash(data:file).map{String(format:"%02x",$0)}.joined())] {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"\r\n\r\n\(value)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(file);add("\r\n--\(boundary)--\r\n")
        return body
    }
    func upload(_ base:URL,key:String,file:Data,name:String,printNow:Bool)async throws->GingerUploadResult {
        let boundary="149-"+UUID().uuidString
        let body=try Self.multipart(file:file,name:name,printNow:printNow,boundary:boundary)
        var r=request(base,"server/files/upload",key:key,method:"POST")
        r.timeoutInterval=120;r.setValue("multipart/form-data; boundary="+boundary,forHTTPHeaderField:"Content-Type")
        let (data,response)=try await session.upload(for:r,from:body)
        let result=try Self.decode(data,response)
        guard let item=result["item"] as? [String:Any],item["root"] as? String=="gcodes",item["path"] as? String==name else {throw Self.failure("无法确认文件上传结果，请到机器网页查看。")}
        return GingerUploadResult(filename:name,started:result["print_started"] as? Bool ?? false,queued:result["print_queued"] as? Bool ?? false)
    }
}

struct GingerPrintSheet:View {
    @ObservedObject var model:Workbench
    @Environment(\.dismiss) private var dismiss
    @State private var address=UserDefaults.standard.string(forKey:"printerWebAddress") ?? ""
    @State private var apiKey=""
    @State private var sending=false
    @State private var attempted=false
    @State private var finished=false
    @State private var notice=""
    @State private var failure=""
    @State private var filename="149_G1_"+UUID().uuidString+".gcode"
    func send(_ printNow:Bool) {
        guard !sending,!attempted,!model.dirty,!model.busy,model.printerModel=="G1",let url=model.gcodeURL else{return}
        let file:Data
        do {file=try Data(contentsOf:url);_ = try PrinterAddress.parse(address)}
        catch {failure=error.localizedDescription;return}
        sending=true;model.busy=true;failure="";notice="正在连接机器…"
        let target=address,key=apiKey,name=filename
        Task { @MainActor in
            defer {sending=false;model.busy=false}
            let client=GingerClient()
            do {
                let base=try await client.resolve(target,key:key)
                if printNow {try await client.ready(base,key:key)}
                UserDefaults.standard.set(target,forKey:"printerWebAddress")
                notice="正在上传切片文件…";attempted=true
                let result=try await client.upload(base,key:key,file:file,name:name,printNow:printNow)
                finished=true
                notice=result.started ? "上传成功，机器已开始打印。":result.queued ? "文件已进入机器队列，尚未开始打印。":printNow ? "上传成功，但机器未开始打印，请打开机器网页查看。":"文件已上传到机器。"
                model.status=notice
            } catch {
                failure=error.localizedDescription
                if attempted {failure+="\n"+L("请求结果未确认，请先到机器网页检查文件和打印状态，不要重复发送。")} 
                notice=""
            }
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            uiText("发送到机器").interfaceFont(.title2,weight:.semibold)
            Text(filename).interfaceFont(.caption).foregroundColor(.secondary).textSelection(.enabled)
            TextField(L("机器 IP 或地址"),text:$address).textFieldStyle(.roundedBorder).disabled(sending || attempted)
            DisclosureGroup(L("连接授权（可选）")) {
                SecureField("Moonraker API Key",text:$apiKey).textFieldStyle(.roundedBorder).disabled(sending || attempted)
                uiText("API Key 仅用于本次窗口，不保存。已授权的局域网通常可留空。").interfaceFont(.caption).foregroundColor(.secondary)
            }
            uiText("上传并打印会立即启动当前切片，请确认目标机器和打印平台已准备好。").interfaceFont(.callout)
            if !notice.isEmpty {HStack {if sending {ProgressView().controlSize(.small)};uiText(notice)}}
            if !failure.isEmpty {uiText(failure).foregroundColor(.orange).interfaceFont(.callout).textSelection(.enabled)}
            HStack {
                Button(L(finished || attempted ? "关闭":"取消")){dismiss()}.disabled(sending)
                Spacer()
                Button(L("仅上传")){send(false)}.disabled(sending || attempted || address.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Button(L("上传并打印")){send(true)}.buttonStyle(.borderedProminent).disabled(sending || attempted || address.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width:530).tint(.gray).interactiveDismissDisabled(sending)
    }
}
