import SwiftUI

struct CalibrationSettings: View {
    @ObservedObject var store: CalibrationStore
    @State private var connection = ScannerConnection.load()
    @State private var notice = ""

    var body: some View {
        TabView {
            AppSettings().tabItem { Label(L("通用"), systemImage: "gearshape") }
            Form {
                TextField(L("设备地址"), text: $connection.host, prompt: uiText("scanner.local"))
                SecureField(L("连接密钥"), text: $connection.token)
                uiText("设备与 Mac 需处于同一局域网。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(L("保存连接")) {
                        do {
                            try connection.save()
                            notice = L("连接已保存。")
                        } catch { notice = error.localizedDescription }
                    }.disabled(store.busy)
                }
                if !notice.isEmpty { uiText(notice).font(.caption) }
            }
            .formStyle(.grouped)
            .frame(width: 440, height: 310)
            .tabItem { Label(L("设备连接"), systemImage: "network") }
        }.padding(12)
    }
}
