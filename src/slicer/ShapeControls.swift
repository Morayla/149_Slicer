import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ShapeControls: View {

    @ObservedObject var model: Workbench
    @State private var wardrobeAdvanced = false
    private var triple: Bool { model.fields["SourceMode"] == "Triple" }
    private var travelTest: Bool { model.fields["SourceMode"] == "TravelTest" }
    private var wardrobe: Bool { model.fields["SourceMode"] == "Wardrobe" }
    private var egg: Bool { model.fields["SourceMode"] == "EggScroll" }
    private var fern: Bool { ["Fern1060", "Fern1060E"].contains(model.fields["SourceMode"] ?? "") }
    private var corner: Bool { model.fields["SourceMode"] == "CornerPipe" }
    private var bud: Bool { model.fields["SourceMode"] == "SingleBud" }
    private var pipeScroll: Bool { model.fields["SourceMode"] == "PipeScroll" }
    private var doubleScroll: Bool { model.fields["SourceMode"] == "DoubleScroll" }
    private var doubleVase: Bool { doubleScroll && model.fields["DoubleLines"] == "3" }
    private var vase: Bool { model.fields["SourceMode"] == "TripleVase" }
    private var bottle: Bool { model.fields["SourceMode"] == "PelletBottle" }
    private var cone: Bool { model.fields["SourceMode"] == "Cone" }
    private var nonplanar: Bool { model.fields["SourceMode"] == "NonplanarCylinder" }
    func row(_ label: String, _ key: String, _ unit: String = "mm") -> some View {
        NumberRow(model: model, label: label, key: key, unit: unit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            ParameterPicker(
                L("外形"), selection: model.binding("SourceMode"),
                options: ShapeParameterRules.catalog.modules.map { .init($0.title, $0.id) }
                    + (model.fields["SourceMode"] == "TravelTest" ? [.init("空移测试", "TravelTest")] : [])
            ).accessibilityLabel(L("造型选择"))
            if model.fields["SourceMode"] == "Hopper" {
                HopperControls(model: model)
            } else if bottle {
                row("瓶身外径", "BottleDiameter")
                row("瓶身高度", "BottleBody")
                row("肩部高度", "BottleShoulder")
                row("瓶口高度", "BottleNeck")
                row("瓶口内径", "BottleBore")
                let h = ["BottleBody", "BottleShoulder", "BottleNeck"].reduce(0.0) {
                    $0 + (Double(model.fields[$1] ?? "0") ?? 0)
                }
                uiText(String(format: L("总高 %.1f mm · 默认约10 L内部容积，不代表10 kg颗粒。"), h)).interfaceFont(.caption)
                    .foregroundColor(.secondary)
                ContextHelp("打印时大底贴平台、瓶口朝上；使用时倒置。实心封底后单墙连续升Z，不加内填充或顶盖。瓶口外径随线宽变化，内径保持设定值。")
                uiText("圆柱—收口两端作短圆滑过渡；切片检查逐圈搭接，实际成形和气密需试印。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if fern {
                row("高度", "FernDepth")
                ContextHelp("正面高1060 × 宽469.9 mm保持不变；躺放45°。进深可在200–500.5 mm内调整，缩短后会重新检查逐圈搭接。")
                uiText("外围裙边关闭，内部清料圈尚未加入；此项只生成本体路径。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if travelTest {
                row("跨孔距离", "TravelTestSpan")
                row("往返轮数", "TravelTestRounds", "轮")
                let rounds = Double(model.fields["TravelTestRounds"] ?? "12") ?? 12
                let retract = model.fields["G1_RETRACT"] ?? "30"
                let extra = model.fields["G1_RESTART_EXTRA"] ?? "10"
                uiText(String(format: L("预计打印高 %.1f mm；含首层和收口约 %.0f 次跨孔移动。"), 2.5 + rounds * 3.5, 2 * rounds + 3))
                    .interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp(
                    "两座矮卷芯交替螺旋上升，起停点放在面向开孔的外露端。默认300 mm跨度、12轮；先用小样观察拉丝、重启缺料与积料。",
                    "固定：线宽8 mm · 双墙净隙1.2 mm · 层高3.5 mm · 首层2.5 mm · 打印9 mm/s · 空移抬升6 mm。",
                    "测试速度为 9 mm/s，测试件居中；不启用底部或象脚补偿。",
                    String(format: L("当前回抽 %@ mm³；重启额外补料 %@ mm³（可在「打印」中调整）。"), retract, extra),
                    "小样不代表最终大跨度或高件已通过。抬升仅提供路径避让；首次试印需观察积料、卷边与喷头净空。"
                )
            } else if wardrobe {
                WardrobeBedTestControls(model: model)
                ParameterPicker(
                    L("打印分件"), selection: model.binding("WardPart"),
                    options: [
                        .init("底梁", "0"), .init("左下段", "1"), .init("右下段", "2"), .init("左上段 · 倒置", "3"),
                        .init("右上段 · 倒置", "4"),
                    ]
                        + (model.fields["WardLayout"] == "1"
                            ? [.init("挂衣矮梁", "5"), .init("左顶部连接段", "6"), .init("右顶部连接段", "7"), .init("顶梁", "8")]
                            : [.init("顶梁", "5")])
                ).disabled(model.toggle("WardBedTest").wrappedValue)
                row("高度", "WardHeight")
                row("开孔展开宽度", "WardOpening")
                row("墙间净距", "WardLaneGap")
                if (Double(model.fields["WardTipClearance"] ?? "0") ?? 0) > 0 {
                    uiText("卷尖至外圈净空已独立锁定，调整墙缝时保持。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if model.fields["WardCoreMode"] == "3" {
                    uiText("数学螺旋 · 粗线宽自动保留卷尖净空 · 管轴位置保留").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if model.fields["WardLayout"] == "2" && !model.toggle("WardBedTest").wrappedValue {
                    ContextHelp("每次切片同时更新单件与整套六件的预计用料、打印时间；六件各打印一次，不含⑦和后装定位套。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                }
                DisclosureGroup(L("结构参数"), isExpanded: $wardrobeAdvanced) {
                    ParameterPicker(
                        L("挂衣方案"),
                        selection: Binding(
                            get: { model.fields["WardLayout"] ?? "0" },
                            set: {
                                model.fields["WardLayout"] = $0
                                model.fields["WardPart"] = "0"
                                model.dirty = true
                            }),
                        options: [.init("原六件 · 直接挂顶梁", "0"), .init("九件 · 独立矮梁", "1"), .init("六件框架 · 挂衣梁后装", "2")])
                    row("上下梁等高", "WardBeam")
                    if model.fields["WardLayout"] == "2" {
                        row("下段高度", "WardLowerHeight")
                        row("顶部开孔圆角", "WardTopRadius")
                    }
                    row("底部开孔圆角", "WardRadius")
                    if model.fields["WardLayout"] == "1" {
                        row("挂衣矮梁高度", "WardRailHeight")
                        row("衣摆距底梁", "WardHemGap")
                    }
                    ParameterPicker(
                        L("卷芯方式"), selection: model.binding("WardCoreMode"),
                        options: [
                            .init("数学螺旋 · 定位套后装", "3"), .init("小卷芯 · 270°包裹", "2"), .init("自然螺旋", "1"),
                            .init("原包管卷芯", "0"),
                        ])
                    if ["2", "3"].contains(model.fields["WardCoreMode"] ?? "0") { row("卷芯最小净空", "WardCoreBore") }
                    if model.fields["WardCoreMode"] != "3" { row("螺旋减卷角度", "WardCurlReduction", "°") }
                    row("连接柱外径", "WardPipeD")
                    row("孔径余量", "WardClearance")
                    row("挂衣数量", "WardCount", "件")
                    row("每件挂放间距", "WardPitch")
                    row("两端挂放余量", "WardEndSpace")
                    ParameterPicker(
                        L("层高策略"), selection: model.binding("WardLayerMode"),
                        options: [.init("圆角细层", "0"), .init("统一约设定层高", "1")])
                }
                ContextHelp("每件双墙连续升 Z，上段倒置打印；层高不超过 3.5 mm。安装与承载需实物验证。")
            } else if egg {
                row("高度", "EggHeight")
                let h = Double(model.fields["EggHeight"] ?? "650") ?? 650
                uiText(String(format: L("进深自动 %.1f mm；宽度与双卷同步缩放。"), h * 80 / 650)).interfaceFont(.caption)
                    .foregroundColor(.secondary)

                ContextHelp("正面朝上平放打印，Z 轴生成进深；打印完成后立起使用。切片会检查卷尖回转与相邻料道净空，过小时提示最小高度。")
            } else if corner {
                row("墙角占位边长", "CornerSide")
                row("高度", "CornerHeight")
                row("连接管外径", "CornerPipeD")
                row("孔径余量", "CornerClearance")
                row("墙间净距", "CornerLaneGap")
                uiText("两只同形双卷，右下角留贯穿管孔；底侧、右侧与 90° 墙面相切。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("管孔直径 = 管外径 + 装配余量。Ø21.3 管配 1 mm 余量，即 Ø22.3 孔、单边 0.5 mm。钢管本身不打印。")
                ContextHelp("截面沿全高一致；闭合双线连续升 Z。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if bud {
                row("参考外径（含料道）", "BudD")
                row("高度", "BudHeight")
                row("基准螺旋圈数", "BudTurns", "圈")
                row("中心净空直径", "BudCoreD")
                row("墙间净距", "BudLaneGap")
                row("卷边收拢角", "BudCurl", "°")
                row("收拢开始高度", "BudStart")
                row("收拢结束高度", "BudEnd")
                ContextHelp("涡心固定，外侧卷边沿高度平滑收拢，形成侧面的 S 形花蕾边；收拢角为 0 时成为直壁螺旋柱。")
            } else if pipeScroll {
                ParameterPicker(
                    L("轮廓样式"), selection: model.binding("PipeScrollProfile"),
                    options: [.init("紧凑卷芯", "0"), .init("同心卷芯", "1"), .init("短卷尖 · 8 mm", "2")])
                row("高度", "PipeScrollHeight")
                if model.fields["PipeScrollProfile"] != "2" { row("两卷芯中心距", "PipeScrollSpacing") }
                if model.fields["PipeScrollProfile"] == "2" {
                    ContextHelp("线宽 8 mm，双墙净隙约 1.5 mm；配 Ø21.3 mm 连接管，定位套另行打印。")
                } else if model.fields["PipeScrollProfile"] == "1" {
                    ContextHelp("同心卷芯：净孔 29.7 mm，线宽 6 mm，双墙净距 3 mm。")
                } else {
                    ContextHelp("紧凑卷芯：净孔 29.7 mm，中心距 120–230 mm。")
                }
                ContextHelp("首层等高闭合，墙体连续升Z，顶部整平。管与固定套另行装配，不作为主体打印；调整高度不改变插管接口。")
            } else if doubleScroll {
                ParameterPicker(
                    L("轮廓样式"), selection: model.binding("DoubleProfile"),
                    options: [
                        .init("镜像双卷", "0"), .init("S 形双卷长灯", "1"), .init("圆弧深卷（对称）", "2"), .init("等距双螺旋（平顺）", "3"),
                    ])
                ParameterPicker(
                    L("走线方式"), selection: model.binding("DoubleLines"),
                    options: [.init("单线开放", "1"), .init("双线闭合", "2"), .init("花瓶模式（连续升 Z）", "3")])
                if ["2", "3"].contains(model.fields["DoubleLines"] ?? "1") {
                    row("墙间净距", "DoubleLaneGap")
                    ContextHelp("一侧绕入，中心圆弧回转，沿另一侧绕出；两瓣连成闭合轮廓。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                }
                if doubleVase {
                    ContextHelp("首层等高，之后连续升 Z；层高是每圈最大上升量，顶部自动整平。")
                    uiText("花瓶模式使用等距双螺旋；需要为两侧料道及内卷回转留出空间。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                row(["2", "3"].contains(model.fields["DoubleProfile"] ?? "0") ? "参考圆外径" : "单瓣外径", "DoubleD")
                row("每侧螺旋圈数", "DoubleTurns", "圈")
                row(["2", "3"].contains(model.fields["DoubleProfile"] ?? "0") ? "两圆参考外缘间距" : "两螺旋外缘间距", "DoubleGap")
                row("高度", "DoubleHeight")
                if model.fields["DoubleProfile"] == "3" {
                    ContextHelp("两侧为等距阿基米德螺旋，支持 1–4 圈及小数；严格旋转对称。调整间距会重新求解平顺过渡，保持连接处方向和曲率连续。")
                } else if model.fields["DoubleProfile"] == "2" {
                    ContextHelp("两侧各含 270° 正圆主弧，内圈渐收；两瓣严格旋转对称，连接处弯曲连续。间距按含线宽的两个参考圆计算。")
                } else {
                    ContextHelp("左右圈数同步，支持 1–4 圈及小数。间距按两瓣相向外缘的净距计算；调整间距只伸缩中间连接段。")
                }
                if model.fields["DoubleProfile"] != "0" {
                    ContextHelp("端面为连续 S 形双卷；灯体长度沿 Z 方向延伸，调整长度不改变端面。打印时长轴竖直，横放后成为长条灯罩。")
                }
                ContextHelp("单瓣外径包含线宽。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if vase {
                row("路径外接直径", "VaseD")
                row("高度", "VaseHeight")
                row("每瓣螺旋圈数", "VaseTurns", "圈")
                row("最小空腔直径", "VaseCoreDiameter")
                ContextHelp("每瓣圈数支持 1–6 圈，可输入 2.5 等小数。").interfaceFont(.caption).foregroundColor(
                    .secondary)
                ContextHelp("空腔直径为扣除线宽后的最小净空；减少圈数后自然变大的空腔会保留。外接直径按路径中心线计算，不含材料宽度。")
                uiText("底部与补偿在下方设置。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if triple {
                row("路径外接直径", "TripleD")
                row("长螺旋圈数", "TripleTurns", "圈")
                row("高度", "TripleHeight")
                uiText("三个螺旋连成闭合路径；直径按路径中心线计算，不含线宽。").interfaceFont(.caption).foregroundColor(
                    .secondary)
            } else if model.fields["SourceMode"] == "Crescent" {
                row("外径", "CrescentD")
                row("高度", "CrescentHeight")
                row("截面厚度", "CrescentThickness")
                row("开口净宽", "CrescentGap")
                row("开口方向", "CrescentRotation", "°")
                row("灯泡参考直径", "CrescentBulbD")
                ContextHelp("一个深弯月围成灯罩，两端圆滑。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("沿月牙边界打印空心壳体；不整块填实，不生成底盘或灯座。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if model.fields["SourceMode"] == "Ellipse" {
                row("长轴外径", "EllipseMajor")
                row("短轴外径", "EllipseMinor")
                row("高度", "EllipseHeight")
                uiText("两轴为完整外径，不是半径。上下截面一致；长短轴相等时为圆柱。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if cone {
                row("下口外径", "ConeBottomD")
                row("上口外径", "ConeTopD")
                row("高度", "ConeHeight")
                ContextHelp("开口锥形 / 圆台灯罩，上下口径均需大于线宽；不收尖封顶。")
            } else {
                row("外径", "Dout")
                row("高度", "CH")
                if nonplanar {
                    row("口沿下凹深度", "NPDepth")
                    row("起伏开始高度", "NPStart")
                    row("下凹方向", "NPDirection", "°")
                    ContextHelp("两高两低，保持中间开口。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                    ContextHelp("已配套非平面走线：从起伏开始高度逐渐变形。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                    uiText("实验样品：喷嘴保持竖直，未校验打印头碰撞；先检查喷嘴周围的避让空间。").interfaceFont(.caption).foregroundColor(.secondary)
                }
            }

            if triple { row("每圈采样数", "TriplePts", "点") }

        }
    }
}
