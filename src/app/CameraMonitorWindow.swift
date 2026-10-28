import SwiftUI

struct CameraMonitorWindow:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @StateObject private var browser=PrinterBrowser(addressKey:"reolinkCameraWebAddress",defaultAddress:"http://192.168.3.28/")
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"video").interfaceFont(.title2)
                uiText("打印监控").interfaceFont(.headline)
                TextField(L("摄像头 IP 或网页地址"),text:$browser.address)
                    .textFieldStyle(.roundedBorder).onSubmit{browser.connect()}
                    .accessibilityLabel(L("摄像头网页地址"))
                Button(L("保存并打开")){browser.connect()}.buttonStyle(.borderedProminent)
                Button(L("刷新")){browser.connect()}.disabled(browser.activeURL==nil)
                Button(L("浏览器打开")){browser.external()}.disabled(browser.address.isEmpty)
            }.padding(16)
            HStack {
                ContextHelp("Reolink E1 Zoom · 首次在摄像头页面登录。远程使用需连接 Tailscale，并启用摄像头地址转接。")
                Spacer()
            }.padding(.horizontal,16).padding(.bottom,12)
            Divider()
            ZStack {
                if browser.activeURL != nil {PrinterWebView(browser:browser)}
                else {
                    VStack(spacing:16) {
                        Image(systemName:"video").interfaceFixedFont(size:44).foregroundColor(.secondary)
                        uiText("连接摄像头").interfaceFont(.title2)
                        uiText("填写 Reolink App 网络信息中的 IP 地址。\n请先在摄像头的服务器设置中开启网页访问。").multilineTextAlignment(.center).foregroundColor(.secondary)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                if let error=browser.error {
                    VStack(alignment:.leading,spacing:12) {
                        uiText("连接提示").interfaceFont(.headline)
                        uiText(error).textSelection(.enabled)
                        uiText("请检查摄像头地址、网页访问设置和网络连接。").foregroundColor(.secondary)
                        HStack {Button(L("重试")){browser.connect()};Button(L("浏览器打开")){browser.external()};Button(L("关闭提示")){browser.error=nil}}
                    }.padding(24).frame(maxWidth:520).background(.regularMaterial).cornerRadius(12).shadow(radius:10)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            Divider()
            HStack {
                if browser.loading {ProgressView().controlSize(.small)}
                if browser.activeURL != nil {uiText(browser.status)} else {uiText("等待摄像头地址")}
                Spacer()
            }.interfaceFont(.caption).padding(12)
        }.frame(minWidth:850,minHeight:600)
        .onAppear {if browser.activeURL==nil && !browser.address.isEmpty {browser.connect()}}
    }
}
