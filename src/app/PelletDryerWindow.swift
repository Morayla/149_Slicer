import SwiftUI
import AppKit

struct PelletDryerWindow:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @StateObject private var browser=PrinterBrowser(addressKey:"pelletDryerWebAddress",defaultAddress:"http://100.97.27.58/")

    private func connect(_ address:String) {
        browser.address=address
        browser.connect()
    }

    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"thermometer.medium").interfaceFont(.title2)
                uiText("颗粒烘干机").interfaceFont(.headline)
                TextField(L("烘干机网页地址"),text:$browser.address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {browser.connect()}
                    .accessibilityLabel(L("烘干机网页地址"))
                Button(L("打开")){browser.connect()}.buttonStyle(.borderedProminent)
                Button(L("刷新")){browser.connect()}.disabled(browser.activeURL==nil)
                Button(L("浏览器打开")){browser.external()}.disabled(browser.address.isEmpty)
            }.padding(16)
            HStack(spacing:12) {
                uiText("远程使用请先连接 Tailscale；烘干机需保持供电和联网。").interfaceFont(.caption).foregroundColor(.secondary)
                Spacer()
                Button(L("远程地址")){connect("http://100.97.27.58/")}
                Button(L("工作室地址")){connect("http://192.168.3.27/")}
            }.padding(.horizontal,16).padding(.bottom,12)
            Divider()
            ZStack {
                if browser.activeURL != nil {PrinterWebView(browser:browser)}
                if let error=browser.error {
                    VStack(alignment:.leading,spacing:12) {
                        uiText("连接提示").interfaceFont(.headline)
                        uiText(error).textSelection(.enabled)
                        uiText("在工作室可尝试工作室地址；在外面请确认 Tailscale 已连接。").foregroundColor(.secondary)
                        HStack {
                            Button(L("重试")){browser.connect()}
                            Button(L("浏览器打开")){browser.external()}
                            Button(L("关闭提示")){browser.error=nil}
                        }
                    }.padding(24).frame(maxWidth:520).background(.regularMaterial).cornerRadius(12).shadow(radius:10)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            Divider()
            HStack {
                if browser.loading {ProgressView().controlSize(.small)}
                uiText(browser.status)
                Spacer()
            }.interfaceFont(.caption).padding(12)
        }.frame(minWidth:850,minHeight:600)
        .onAppear {if browser.activeURL==nil {browser.connect()}}
    }
}
