import SwiftUI
import WebKit
import AppKit

final class PrinterBrowser:NSObject,ObservableObject,WKNavigationDelegate,WKUIDelegate {
    private let addressKey:String
    @Published var address:String
    @Published var activeURL:URL?
    @Published var loading=false
    @Published var error:String?
    @Published var status="填写机器地址，打开它的 Mainsail / Fluidd 网页。"
    init(addressKey:String="printerWebAddress", defaultAddress:String="") {
        self.addressKey=addressKey
        self.address=UserDefaults.standard.string(forKey:addressKey) ?? defaultAddress
        super.init()
    }
    lazy var webView:WKWebView = {
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view=WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate=self;view.uiDelegate=self
        view.allowsBackForwardNavigationGestures=true
        return view
    }()
    func connect() {
        do {
            let url=try PrinterAddress.parse(address)
            address=url.absoluteString;UserDefaults.standard.set(address,forKey:addressKey)
            activeURL=url;error=nil;loading=true;status="正在打开 \(url.host ?? address)…"
            webView.load(URLRequest(url:url,timeoutInterval:20))
        } catch {self.error=error.localizedDescription;loading=false}
    }
    func clear() {
        webView.stopLoading();webView.loadHTMLString("",baseURL:nil)
        UserDefaults.standard.removeObject(forKey:addressKey)
        address="";activeURL=nil;error=nil;loading=false;status="已清除机器地址。"
    }
    func external() {
        do {let url=try PrinterAddress.parse(address);NSWorkspace.shared.open(url)}
        catch {self.error=error.localizedDescription}
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        guard activeURL != nil else{return}
        loading=false;status="网页已加载 · \(webView.url?.host ?? "")"
    }
    func failed(_ failure:Error) {
        guard activeURL != nil,(failure as NSError).code != NSURLErrorCancelled else{return}
        loading=false;error="网页未能打开：\(failure.localizedDescription)\n请确认 IP、端口和网络连接，也可尝试在浏览器打开。";status="连接未完成"
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {failed(error)}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {failed(error)}
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        let scheme=action.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["http","https","about","blob"].contains(scheme) ? .allow:.cancel)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if action.targetFrame==nil,let url=action.request.url,["http","https"].contains(url.scheme?.lowercased() ?? "") {webView.load(action.request)}
        return nil
    }
    // Website buttons such as file upload use the standard macOS chooser.
    func webView(_ webView:WKWebView,runOpenPanelWith parameters:WKOpenPanelParameters,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping([URL]?)->Void) {
        let panel=NSOpenPanel();panel.allowsMultipleSelection=parameters.allowsMultipleSelection
        panel.canChooseDirectories=parameters.allowsDirectories
        panel.begin {response in completionHandler(response == .OK ? panel.urls:nil)}
    }
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping()->Void) {
        self.error=message;completionHandler()
    }
    func webView(_ webView:WKWebView,runJavaScriptConfirmPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(Bool)->Void) {
        let alert=NSAlert();alert.messageText=message;alert.addButton(withTitle:L("确定"));alert.addButton(withTitle:L("取消"));completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

struct PrinterWebView:NSViewRepresentable {
    let browser:PrinterBrowser
    func makeNSView(context:Context)->WKWebView {browser.webView}
    func updateNSView(_ view:WKWebView,context:Context) {}
}

struct PrinterWindow:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @StateObject private var browser=PrinterBrowser()
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                FabricationIcon()
                TextField(L("IP 或网页地址，例如 192.168.1.100"),text:$browser.address).textFieldStyle(.roundedBorder).onSubmit{browser.connect()}.accessibilityLabel(L("打印机网页地址"))
                Button(L("保存并打开")){browser.connect()}.buttonStyle(.borderedProminent)
                Button(L("浏览器打开")){browser.external()}.disabled(browser.address.isEmpty)
                Button(L("清除")){browser.clear()}.disabled(browser.address.isEmpty && browser.activeURL==nil)
            }.padding(16)
            HStack {
                ContextHelp("机器地址保存在此电脑，切换造型项目仍可使用。填写网页端口；无需填写 Moonraker API 地址。")
                Spacer()
                Button(L("刷新")){browser.connect()}.disabled(browser.activeURL==nil)
            }.padding(.horizontal,16).padding(.bottom,12)
            Divider()
            ZStack {
                if browser.activeURL != nil {PrinterWebView(browser:browser)}
                else {
                    VStack(spacing:14) {
                        Image(systemName:"network").interfaceFixedFont(size:44).foregroundColor(.secondary)
                        uiText("连接你的 G1 打印机").interfaceFont(.title2)
                        uiText("电脑与打印机连接到可互通的网络。\n输入机器 IP，可带端口号；也支持 .local 主机名和完整网址。").multilineTextAlignment(.center).foregroundColor(.secondary)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                if let error=browser.error {
                    VStack(alignment:.leading,spacing:12) {
                        uiText("连接提示").interfaceFont(.headline)
                        uiText(error).textSelection(.enabled)
                        HStack {Button(L("重试")){browser.connect()};Button(L("关闭提示")){browser.error=nil}}
                    }.padding(24).frame(maxWidth:500).background(.regularMaterial).cornerRadius(12).shadow(radius:10)
                }
            }
            Divider()
            HStack {if browser.loading {ProgressView().controlSize(.small)};uiText(browser.status);Spacer()}.interfaceFont(.caption).padding(12)
        }.frame(minWidth:850,minHeight:600)
        .onAppear {if browser.activeURL==nil && !browser.address.isEmpty {browser.connect()}}
    }
}
