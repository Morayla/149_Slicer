import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WaveControls: View {

    @ObservedObject var model: Workbench
    func row(_ label: String, _ key: String, _ unit: String = "mm") -> some View {
        NumberRow(model: model, label: label, key: key, unit: unit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParameterPicker(
                L("类型"), selection: model.modifierSelection,
                options: [
                    .init("无", "none"), .init("随机波", "noise", enabled: model.supportsNoise),
                    .init("三角波", "wave", enabled: model.supportsEffects),
                    .init("网孔", "mesh", enabled: model.supportsMesh),
                ])
            if model.toggle("NoiseEnabled").wrappedValue {
                row("纹理强度", "NoiseStrength", "×")
                row("起伏幅度", "NoiseAmplitude")
                row("波纹尺度", "NoiseScale")
                row("层间变化", "NoiseVariation", "%")
                row("随机种子", "NoiseSeed", "")
                Toggle(L("垂直微起伏"), isOn: model.toggle("NoiseZEnabled"))
                if model.toggle("NoiseZEnabled").wrappedValue { row("垂直起伏幅度", "NoiseZAmplitude") }
                ContextHelp("适用于圆柱与圆台。轮廓向内、向外起伏；可叠加 Z 起伏，底部保持平整。")
                ContextHelp("尺度越大波纹越宽缓；层间变化越大，上下圈差异越明显。种子相同，纹理相同。")
                uiText("幅度和尺度会按线宽、EF 与采样自动限制，以保留层间搭接。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("垂直幅度自动限制在实际圈间高度的 10% 内；按局部间距和三维线长调整出料，首尾平缓过渡。")
                if let fit = model.preview?.noise_fit, !model.dirty {
                    uiText(String(format: L("实际幅度上限 %.3f mm · 波纹尺度约 %.2f mm"), fit.effective, fit.scale)).interfaceFont(
                        .caption)
                    if let z = fit.z_effective, z > 0 {
                        uiText(String(format: L("实际垂直幅度上限 %.3f mm"), z)).interfaceFont(.caption)
                    }
                }
            }
            if model.toggle("MeshEnabled").wrappedValue {
                if model.printerModel != "G1" {
                    Button(L("按喷嘴设置网孔参数")) {
                        let nozzle = Double(model.fields["Nozzle"] ?? "0.4") ?? 0.4
                        let width = Double(model.fields["W"] ?? "0.45") ?? 0.45
                        model.fields["MeshStrand"] = String(format: "%.3g", min(nozzle * 0.5, width * 0.8))
                        model.fields["MeshOpening"] = String(format: "%.3g", nozzle * 2.5)
                        model.fields["MeshSpeed"] = "5"
                        model.dirty = true
                    }
                    uiText("此按钮仅设置料线厚度、网孔高度与网孔速度，不更改造型尺寸。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                row("每圈波数", "MeshCount", "个")
                row("网孔高度上限", "MeshOpening")
                row("料线厚度", "MeshStrand")
                row("接点压合量", "MeshContactPress")
                row("接点搭接长度", "MeshContactLength")
                ContextHelp("压合量缩小接点间距，不减少料线出料；上限为料线厚度的 25%。搭接长度沿轮廓测量，0 为原波形。接点连续走线，不停顿。")
                row("网孔速度上限", "MeshSpeed", "mm/s")
                ContextHelp("支持 Ginger G1、H2D、P1P、A1 与 A1 mini 的圆柱／椭圆柱。请关闭 EF；普通打印机同时受最大体积流量限速。")
                ContextHelp("波数自动匹配半整数，让上下圈错开半波；网孔高度随总高度适配。首尾各一圈渐变接入。")
                if let fit = model.preview?.mesh_fit, !model.dirty {
                    uiText(String(format: L("实际：%g 波/圈 · 网孔 %.2f mm · %d 圈"), fit.effective, fit.opening, fit.turns))
                        .interfaceFont(.caption)
                }
                ContextHelp("跨空段保持料线出料，不补满网孔。预览不模拟下垂；先用低速短样品验证粘接与喷嘴间隙。")
            }
            if model.toggle("WaveEnabled").wrappedValue {
                row("波峰幅度", "WaveAmp")
                row("波谷幅度", "WaveNegAmp")
                row("每圈波数", "WaveCount", "个")
                if ["Cylinder", "Ellipse", "Cone"].contains(model.fields["SourceMode"] ?? "") {
                    Toggle(L("自动匹配波数"), isOn: model.toggle("WaveAutoFit"))
                    ContextHelp("切片时校核：1,2 交替匹配最近的半整数（40 → 39.5）；重复同一波形匹配整数。调整后更新输入框，并写入项目和 G-code。")
                    uiText(
                        model.fields["SourceMode"] == "Ellipse"
                            ? "波形沿椭圆周长均分，避免两端疏密不均；EF 改变周长时，毫米波距随之变化。" : "按圆周等分波距；锥体或 EF 变径时，毫米波距随周长变化。起始接入和最终截断除外。"
                    ).interfaceFont(.caption).foregroundColor(.secondary)
                    if let fit = model.preview?.wave_fit, !model.dirty {
                        uiText(String(format: L("波数校核：%g → %g 波/遍。"), fit.requested, fit.effective)).interfaceFont(
                            .caption)
                        if fit.kind == "transitions" {
                            uiText("当前排列包含模式切换，过渡处不能保证等距。").interfaceFont(.caption).foregroundColor(.orange)
                        }
                    }
                }
                if model.fields["SourceMode"] == "Triple" {
                    uiText("三螺旋需较多波数。400 mm、3 圈示例可从 200 波预览；波数太少会跨过盘绕路径。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                }
                row("前几遍保持原形", "WaveStartLayer", "遍")
                uiText("循环排列 · 0 原形 / 1 波形 A / 2 波形 B").interfaceFont(.subheadline)
                TextEditor(text: model.binding("WavePattern")).font(.system(.body, design: .monospaced)).frame(
                    height: 85
                ).padding(6).background(Color(nsColor: .textBackgroundColor)).cornerRadius(6)
                if model.fields["SourceMode"] == "Triple" {
                    ContextHelp("排列循环：1 与 2 在主体区域固定错开半个波长，仅在接缝两侧各约两个波长内过渡。一遍指沿整个闭合造型走一遍。")
                } else {
                    ContextHelp("半整数波数让 1,2 沿整条路径连续交替，每圈自然错开半波，接缝不另补短波。整数配合 1,2 会保留相位切换；插入 0 或改变排列仍有过渡。")
                }
                ParameterPicker(
                    L("Z 走法"), selection: model.binding("WaveZMode"),
                    options: [.init("局部等高", "Source"), .init("连续螺旋上升", "Continuous")])
                ContextHelp(
                    "两种走法每遍波数相同。连续螺旋上升：沿路径持续升 Z。局部等高：波谷到波峰升 Z，波峰到波谷保持水平；接缝边走边升，不原地抬升。",
                    "三螺旋沿局部轮廓法线偏移。较大的波幅可能使相邻分支接近或交叉；先查看预览。流量按新路径长度与规划层高重新计算，不是材料变形模拟。"
                )
            }
        }
    }
}
