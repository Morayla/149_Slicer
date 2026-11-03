import SwiftUI

struct ViewportIconButton: View {
    let title: String
    let symbol: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                .frame(width: 30, height: 28)
                .background(selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.borderless).help(L(title)).accessibilityLabel(L(title))
    }
}

struct ViewportPanelHandle: View {
    var scope = "workspace"
    var backgroundWhite = false
    let leading: Bool
    let expanded: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule().fill((backgroundWhite ? Color.black : Color.white).opacity(hovering ? 0 : 0.30)).frame(width: 3, height: 26)
                Image(systemName: leading == expanded ? "chevron.left" : "chevron.right")
                    .font(.caption).opacity(hovering ? 1 : 0)
            }.frame(width: 20, height: 54).contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.foregroundStyle(backgroundWhite ? Color.black : Color.white).buttonStyle(.plain).onHover { hovering = $0 }
            .help(L(leading ? (expanded ? "收起参数" : "展开参数") : (expanded ? "收起测量" : "展开测量")))
            .accessibilityLabel(L(leading ? "切换参数栏" : "切换结果栏"))
            .accessibilityIdentifier(scope + (leading ? ".parameters" : ".results"))
    }
}

struct ViewportBackgroundButton: View {
    @Binding var white: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: ViewportBackgroundTransition.duration)) { white.toggle() }
        } label: {
            ZStack {
                Image(systemName: "sun.max").opacity(white ? 1 : 0)
                Image(systemName: "moon").opacity(white ? 0 : 1)
            }.font(.system(size: 14)).frame(width: 30, height: 28).contentShape(Rectangle())
        }.buttonStyle(.borderless)
            .help(L(white ? "切换为黑色背景" : "切换为白色背景"))
            .accessibilityLabel(L(white ? "切换为黑色背景" : "切换为白色背景"))
    }
}
