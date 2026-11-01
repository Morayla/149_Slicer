import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PrintStatistics: View {

    let summary: PreviewResult.Summary
    private var minutes: Int { max(1, Int(ceil(summary.motion_minutes))) }
    func number(_ value: String) -> some View {
        uiText(value).interfaceFixedFont(size: 28, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(
            0.8)
    }
    func unit(_ value: String) -> some View { uiText(value).interfaceFont(.subheadline).foregroundColor(.secondary) }
    func card<Value: View>(
        _ title: String, _ icon: String, _ detail: String, _ footnote: String, @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L(title), systemImage: icon).interfaceFont(.subheadline).foregroundColor(.secondary)
            value().frame(height: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                uiText(detail)
                uiText(footnote)
            }.interfaceFont(.caption).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.75).frame(
                height: 34, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard()
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            card(
                summary.assembly == nil ? "材料用量" : "当前件用料", "scalemass",
                String(
                    format: L("模型 %.1f g · 裙边 %.1f g · 额外 %.1f g"), summary.model_mass_g, summary.skirt_mass_g,
                    summary.extra_mass_g),
                String(format: L("密度 %.3g g/cm³ · 体积 %.1f cm³"), summary.density_g_cm3, summary.volume_mm3 / 1000)
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    number(String(format: "%.1f", summary.mass_g))
                    unit("g")
                }
            }
            if let assembly = summary.assembly {
                card("整套六件预计用料", "shippingbox", "①至⑥各一件 · 含各件额外耗料", "不含⑦、定位套和管材 · 轮廓积分预估") {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        unit("约")
                        number(String(format: "%.0f", assembly.mass_g))
                        unit("g")
                    }
                }
            }

            if let total = summary.assembly?.motion_minutes {
                let duration = max(1, Int(ceil(total)))
                card("整套六件预计时间", "clock.arrow.circlepath", "①至⑥各打印一次的累计用时", "不含预热、调平、加减速及换件") {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        unit("约")
                        number("\(duration/60)")
                        unit("小时")
                        number("\(duration%60)")
                        unit("分")
                    }
                }
            }
            card(summary.assembly == nil ? "预计打印时间" : "当前件预计时间", "clock", "包含打印与空移的指令用时", "不含预热、调平和加减速影响") {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if minutes >= 60 {
                        number("\(minutes/60)")
                        unit("小时")
                    }
                    number("\(minutes%60)")
                    unit("分钟")
                }
            }
        }
    }
}
