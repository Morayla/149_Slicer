import SwiftUI

struct SliceLegend: View {
    let data: PreviewResult
    let mode: PreviewMode
    let showTravel: Bool
    let white: Bool
    @State private var expanded = true
    @State private var roles: [Int] = []
    @State private var heights = LayerHeightColors(heights: [])
    private let labels = ["裙边", "底部", "墙体", "收尾", "空移"]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    uiText(mode.rawValue).font(.caption)
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(L(expanded ? "收起图例" : "展开图例"))
            if expanded {
                if mode == .role {
                    ForEach(roles.filter { $0 != 4 || showTravel }, id: \.self) { role in
                        swatch(previewRoleColors[role], labels[role])
                    }
                } else if mode == .height {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(heights.entries) { entry in
                                swatch(Color(red: entry.rgb[0], green: entry.rgb[1], blue: entry.rgb[2]), entry.label + " mm")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: min(132, CGFloat(heights.entries.count) * 20))
                } else {
                    let limits = data.limits(mode, true)
                    LinearGradient(colors: (0...8).map { metricColor(Double($0) / 8) }, startPoint: .leading, endPoint: .trailing)
                        .frame(height: 7).clipShape(Capsule())
                    HStack {
                        Text(mode.label(limits[0]))
                        Spacer(minLength: 4)
                        Text(mode.label(limits[1]))
                    }.font(.caption2).monospacedDigit()
                    Text(mode.unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(10).frame(width: 148).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, white ? .light : .dark)
            .accessibilityIdentifier("slicer.legend")
            .task(id: data.sha256) {
                let result = await Task.detached(priority: .userInitiated) {
                    (Array(Set(data.segments.map { Int($0[6]) })).sorted(), LayerHeightColors(heights: data.layer_heights ?? []))
                }.value
                guard !Task.isCancelled else { return }
                roles = result.0; heights = result.1
            }
    }
    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 16, height: 9)
            uiText(title).font(.caption).monospacedDigit()
        }
    }
}
