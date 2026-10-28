import Foundation

enum PrinterAddress {
    static func parse(_ text:String)throws->URL {
        let raw=text.trimmingCharacters(in:.whitespacesAndNewlines)
        func invalid(_ reason:String)->NSError {NSError(domain:"G1Mini.Printer",code:1,userInfo:[NSLocalizedDescriptionKey:reason])}
        guard !raw.isEmpty else {throw invalid("请填写打印机 IP 或网页地址。")}
        guard raw.rangeOfCharacter(from:.whitespacesAndNewlines)==nil else {throw invalid("地址中不能包含空格。")}
        let value=raw.contains("://") ? raw:"http://"+raw
        guard let parts=URLComponents(string:value),let scheme=parts.scheme?.lowercased(),["http","https"].contains(scheme),
              let host=parts.host,!host.isEmpty,let url=parts.url else {throw invalid("请输入有效的 HTTP / HTTPS 网页地址，例如 192.168.1.100:8080。")}
        guard parts.user==nil,parts.password==nil else {throw invalid("请在打印机网页中登录，不要把密码写在地址里。")}
        if let port=parts.port,!(1...65535).contains(port) {throw invalid("端口号应在 1–65535 之间。")}
        if host.allSatisfy({$0.isNumber || $0=="."}) {
            let octets=host.split(separator:".",omittingEmptySubsequences:false)
            guard octets.count==4,octets.allSatisfy({Int($0).map{(0...255).contains($0)} ?? false}) else {throw invalid("IPv4 地址应为四段 0–255 的数字。")}
        }
        return url
    }
}
