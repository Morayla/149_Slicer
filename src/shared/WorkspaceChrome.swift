import SwiftUI

enum WorkspaceLayout {
    static let sidebarWidth: CGFloat = 350
    static let valueWidth: CGFloat = 82
    static let unitWidth: CGFloat = 38
    static let rowHeight: CGFloat = 30
}

struct WorkspaceHeader<Actions: View>: View {
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(
                nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "logo", withExtension: "pdf")!)!
            )
            .renderingMode(.template).resizable().scaledToFit().foregroundStyle(.primary)
            .frame(width: 68, height: 44).padding(.horizontal, 12)
            .frame(height: 60).glassCard().accessibilityLabel(L("149 标志"))
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                actions
            }.padding(.horizontal, 16).frame(height: 60).glassCard()
        }.padding(.horizontal, 10).padding(.top, 10)
    }
}
