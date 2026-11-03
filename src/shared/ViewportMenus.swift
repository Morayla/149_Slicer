import AppKit
import SwiftUI

enum ViewportMenu { case display, camera }

struct ViewportMenuRow: View {
    enum Selection { case single, toggle, action }
    let title: String
    var selected = false
    var selection: Selection = .toggle
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selection == .single
                    ? (selected ? "largecircle.fill.circle" : "circle")
                    : (selected ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 12)).opacity(selection == .action ? 0 : (selected ? 1 : 0.55)).frame(width: 16)
                uiText(title)
                Spacer(minLength: 0)
            }.frame(minHeight: 24).padding(.horizontal, 4).contentShape(Rectangle())
                .background(.primary.opacity(hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .onHover { hovered = $0 }
    }
}

struct ViewportMenus<Display: View, Camera: View>: View {
    @Binding var white: Bool
    @Binding var menu: ViewportMenu?
    let scope: String
    @ViewBuilder var display: () -> Display
    @ViewBuilder var camera: () -> Camera
    @State private var contentHeight: CGFloat = 220

    var body: some View {
        GeometryReader { canvas in
            ZStack(alignment: .topTrailing) {
                if menu != nil {
                    Color.clear.contentShape(Rectangle()).onTapGesture { menu = nil }
                }
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 3) {
                        ViewportBackgroundButton(white: $white)
                        ViewportIconButton(title: "显示", symbol: "eye", selected: menu == .display) { toggle(.display) }
                            .accessibilityIdentifier(scope + ".display")
                        ViewportIconButton(title: "视角", symbol: "rotate.3d", selected: menu == .camera) { toggle(.camera) }
                            .accessibilityIdentifier(scope + ".camera")
                    }.padding(2).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    if let menu {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                if menu == .display { display() } else { camera() }
                            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                        }.scrollIndicators(.automatic)
                            .frame(width: min(menu == .camera ? 164 : 196, max(0, canvas.size.width - 20)),
                                   height: min(contentHeight, max(0, canvas.size.height - 64)))
                            .background(white ? Color.white.opacity(0.94) : Color(white: 0.12).opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.18), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                            .accessibilityIdentifier(scope + ".viewportMenu")
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    }
                }.padding(10)
            }.frame(width: canvas.size.width, height: canvas.size.height, alignment: .topTrailing)
                .background(ViewportMenuDismissMonitor(open: menu != nil) { menu = nil }.allowsHitTesting(false))
                .animation(.easeInOut(duration: 0.18), value: menu)
        }.controlSize(.small).font(.body)
            .environment(\.colorScheme, white ? .light : .dark)
    }
    private func toggle(_ value: ViewportMenu) { menu = menu == value ? nil : value }
}

private struct ViewportMenuDismissMonitor: NSViewRepresentable {
    let open: Bool
    let dismiss: () -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.install(view: view, open: open, dismiss: dismiss)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }
    final class Coordinator {
        var monitor: Any?
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        func install(view: NSView, open: Bool, dismiss: @escaping () -> Void) {
            remove()
            guard open else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak view] event in
                if event.type == .keyDown, event.keyCode == 53 { dismiss(); return nil }
                if event.type == .leftMouseDown, let view,
                   event.window !== view.window || !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                    dismiss()
                }
                return event
            }
        }
    }
}
