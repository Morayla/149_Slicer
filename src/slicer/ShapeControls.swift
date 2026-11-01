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

            Picker(L("造型"), selection: model.binding("SourceMode")) {
                Section(L("灯罩与容器")) {
                    uiText("圆柱灯罩").tag("Cylinder")
                    uiText("椭圆柱").tag("Ellipse")
                    uiText("锥形灯罩").tag("Cone")
                    uiText("起伏口沿圆柱").tag("NonplanarCylinder")
                    uiText("单弯月灯罩").tag("Crescent")
                    uiText("单螺旋花蕾").tag("SingleBud")
                    uiText("双螺旋体").tag("DoubleScroll")
                    uiText("三螺旋体").tag("Triple")
                    uiText("三螺旋花瓶").tag("TripleVase")
                    uiText("10 L 颗粒料瓶 · 花瓶模式").tag("PelletBottle")
                    uiText("Ø210 可调高料桶 · 固定锥嘴").tag("Hopper")
                }
                Section(L("结构件")) {
                    uiText("螺旋挂衣体").tag("Wardrobe")
                    uiText("墙角双卷 · 连接管").tag("CornerPipe")
                    uiText("蛋形海螺双卷").tag("EggScroll")
                    uiText("圆拱双卷支架 · 1060").tag("Fern1060")
                    uiText("圆拱双卷支架 · 1060 E").tag("Fern1060E")
                    uiText("镜像双螺旋 · 插管型").tag("PipeScroll")
                }
                Section(L("导入与测试")) {
                    uiText("导入模型").tag("Imported")
                    uiText("跨孔空移测试 · 双卷芯").tag("TravelTest")
                }
            }.accessibilityLabel(L("造型选择"))
            if model.fields["SourceMode"] == "Imported" {
                Button(L("选择 STL / OBJ / STEP…"), action: model.importModel).frame(
                    maxWidth: .infinity, alignment: .leading)
                Text(verbatim: URL(fileURLWithPath: model.fields["ImportFile"] ?? "").lastPathComponent).interfaceFont(
                    .caption
                ).lineLimit(2).truncationMode(.middle)
                row("缩放比例", "ImportScale", "×")
                ContextHelp(
                    "Z 轴向上，自动落到平台；STL / OBJ 单位按毫米读取。导入外轮廓生成单壁，不沿用原模型壁厚。",
                    "STEP 使用内置原生 CAD 引擎读取。支持每层一个外轮廓的灯罩；分离轮廓、破洞或不支持的悬垂会提示错误。"
                )
            } else if model.fields["SourceMode"] == "Hopper" {
                HopperControls(model: model)
            } else if bottle {
                row("瓶身外径", "BottleDiameter")
                row("直身高度", "BottleBody")
                row("收口高度", "BottleShoulder")
                row("直口高度", "BottleNeck")
                row("瓶口内径", "BottleBore")
                let h = ["BottleBody", "BottleShoulder", "BottleNeck"].reduce(0.0) {
                    $0 + (Double(model.fields[$1] ?? "0") ?? 0)
                }
                uiText(String(format: L("总高 %.1f mm · 默认约10 L内部容积，不代表10 kg颗粒。"), h)).interfaceFont(.caption)
                    .foregroundColor(.secondary)
                ContextHelp("打印时大底贴平台、瓶口朝上；使用时倒置。实心封底后单墙连续升Z，不加内填充或顶盖。瓶口外径随线宽变化，内径保持设定值。")
                uiText("圆柱—收口两端作短圆滑过渡；切片检查逐圈搭接，实际成形和气密需试印。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if fern {
                row("打印高度 / 进深", "FernDepth")
                ContextHelp(
                    "正面高1060 × 宽469.9 mm保持不变；躺放45°。进深可在200–500.5 mm内调整，缩短后会重新检查逐圈搭接。",
                    "原版 / E版共享当前进深、层高与线宽；切换后点切片，比较下方材料用量。E版只截短卷尖，预计少约1.28%用料，并非整圈减半。独立上限50万段。"
                )
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
                    "外围先打印一圈裙边，主体与裙边均为9 mm/s。沿用当前G1温度、回抽及重启补料；测试件固定居中。效果、EF与起始减流不参与。",
                    String(format: L("当前回抽 %@ mm³；重启额外补料 %@ mm³（可在「打印」中调整）。"), retract, extra),
                    "小样不代表最终大跨度或高件已通过。抬升仅提供路径避让；首次试印需观察积料、卷边与喷头净空。"
                )
            } else if wardrobe {
                WardrobeBedTestControls(model: model)
                Picker(L("打印分件"), selection: model.binding("WardPart")) {
                    uiText("①底梁 · 整件").tag("0")
                    uiText("②左下段").tag("1")
                    uiText("③右下段").tag("2")
                    uiText("④左上段 · 倒置打印").tag("3")
                    uiText("⑤右上段 · 倒置打印").tag("4")
                    if model.fields["WardLayout"] == "1" {
                        uiText("独立挂衣矮梁").tag("5")
                        uiText("左顶部连接段").tag("6")
                        uiText("右顶部连接段").tag("7")
                        uiText("顶梁").tag("8")
                    } else {
                        uiText("⑥顶梁 · 整件").tag("5")
                    }
                }.pickerStyle(.menu).disabled(model.toggle("WardBedTest").wrappedValue)
                row("整体高度", "WardHeight")
                row("开孔展开宽度", "WardOpening")
                row("双墙净间隙", "WardLaneGap")
                if (Double(model.fields["WardTipClearance"] ?? "0") ?? 0) > 0 {
                    uiText("卷尖至外圈净空已独立锁定，调整墙缝时保持。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if model.fields["WardCoreMode"] == "3" {
                    uiText("数学螺旋 · 粗线宽自动保留卷尖净空 · 管轴位置保留").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if model.fields["WardLayout"] == "2" && !model.toggle("WardBedTest").wrappedValue {
                    uiText("每次切片同时更新单件与整套六件的预计用料、打印时间；六件各打印一次，不含⑦和后装定位套。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                }
                DisclosureGroup(L("结构参数"), isExpanded: $wardrobeAdvanced) {
                    Picker(
                        L("挂衣方案"),
                        selection: Binding(
                            get: { model.fields["WardLayout"] ?? "0" },
                            set: {
                                model.fields["WardLayout"] = $0
                                model.fields["WardPart"] = "0"
                                model.dirty = true
                            })
                    ) {
                        uiText("原六件 · 直接挂顶梁").tag("0")
                        uiText("九件 · 独立矮梁").tag("1")
                        uiText("六件框架 · 挂衣梁后装").tag("2")
                    }
                    row("上下梁等高", "WardBeam")
                    if model.fields["WardLayout"] == "2" {
                        row("下段打印高度", "WardLowerHeight")
                        row("顶部开孔圆角", "WardTopRadius")
                    }
                    row("底部开孔圆角", "WardRadius")
                    if model.fields["WardLayout"] == "1" {
                        row("挂衣矮梁高度", "WardRailHeight")
                        row("衣摆距底梁", "WardHemGap")
                    }
                    Picker(L("卷芯方式"), selection: model.binding("WardCoreMode")) {
                        uiText("数学螺旋 · 定位套后装").tag("3")
                        uiText("小卷芯 · 270°包裹").tag("2")
                        uiText("自然螺旋").tag("1")
                        uiText("原包管卷芯").tag("0")
                    }
                    if ["2", "3"].contains(model.fields["WardCoreMode"] ?? "0") { row("卷芯最小净空", "WardCoreBore") }
                    if model.fields["WardCoreMode"] != "3" { row("螺旋减卷角度", "WardCurlReduction", "°") }
                    row("连接柱外径", "WardPipeD")
                    row("直径装配余量", "WardClearance")
                    row("挂衣数量", "WardCount", "件")
                    row("每件挂放间距", "WardPitch")
                    row("两端挂放余量", "WardEndSpace")
                    Picker(L("层高策略"), selection: model.binding("WardLayerMode")) {
                        uiText("圆角细层").tag("0")
                        uiText("统一约设定层高").tag("1")
                    }
                }
                ContextHelp("每件双墙连续升 Z，无跨孔空移；上段倒置打印。首层与收口除外，主体按所设层高连续升 Z（支持至3.5 mm）。安装与承载仍需实物验证。")
            } else if egg {
                row("整体高度（使用时）", "EggHeight")
                let h = Double(model.fields["EggHeight"] ?? "650") ?? 650
                uiText(String(format: L("进深自动 %.1f mm；宽度与双卷同步缩放。"), h * 80 / 650)).interfaceFont(.caption)
                    .foregroundColor(.secondary)
                uiText("只需改整体高度。蛋形比例、顶部短平面和海螺卷保持一致；打印线宽不随造型缩放。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("正面朝上平放打印，Z 轴生成进深；打印完成后立起使用。切片会检查卷尖回转与相邻料道净空，过小时提示最小高度。")
            } else if corner {
                row("墙角占位边长", "CornerSide")
                row("模块高度", "CornerHeight")
                row("连接管外径", "CornerPipeD")
                row("直径装配余量", "CornerClearance")
                row("双线净间隙", "CornerLaneGap")
                uiText("两只同形双卷，右下角留贯穿管孔；底侧、右侧与 90° 墙面相切。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("管孔直径 = 管外径 + 装配余量。Ø21.3 管配 1 mm 余量，即 Ø22.3 孔、单边 0.5 mm。钢管本身不打印。")
                uiText("截面沿全高一致；闭合双线连续升 Z。改变尺寸后会重新检查通孔与料道间距。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if bud {
                row("参考外径（含料道）", "BudD")
                row("模块高度", "BudHeight")
                row("基准螺旋圈数", "BudTurns", "圈")
                row("涡心净空直径", "BudCoreD")
                row("双线净间隙", "BudLaneGap")
                row("卷边收拢角", "BudCurl", "°")
                row("收拢开始高度", "BudStart")
                row("收拢结束高度", "BudEnd")
                row("整体朝向", "BudRot", "°")
                ContextHelp(
                    "涡心固定，外侧卷边沿高度平滑收拢，形成侧面的 S 形花蕾边；收拢角为 0 时成为直壁螺旋柱。",
                    "一个螺旋，双壁闭合走线。卷入、内端折返、卷出、外端闭合时均连续升 Z；两道壁分别占用一个线宽。",
                    "外径为包含料道的参考圆上限；检查路径相交和层间搭接。过矮或收拢过急时，请减小层高或加长收拢区间。"
                )
            } else if pipeScroll {
                Picker(L("轮廓样式"), selection: model.binding("PipeScrollProfile")) {
                    uiText("原插管型").tag("0")
                    uiText("同心顺滑 · 原尺寸").tag("1")
                    uiText("8毫米线宽 · 卷尖加回15°").tag("2")
                }.pickerStyle(.menu)
                row("总高度", "PipeScrollHeight")
                if model.fields["PipeScrollProfile"] != "2" { row("两卷芯中心距", "PipeScrollSpacing") }
                row("平面旋转", "PipeScrollRot", "°")
                if model.fields["PipeScrollProfile"] == "2" {
                    ContextHelp(
                        "当前确认版：外形约285.2 × 118.3 mm；8 mm线宽，双墙净隙约1.5 mm。卷尖比红线截短版加回15°，两侧对称。完整蓝套内孔21.7、外径25.7 mm，配21.3 mm管；蓝套另行打印，当前用料不包含插套。"
                    )
                } else if model.fields["PipeScrollProfile"] == "1" {
                    ContextHelp(
                        "同心顺滑确认版：Ø21.3 mm管位于卷芯中心，通过独立定位套装配。卷芯净空29.7 mm，线宽6 mm，双墙净隙3 mm。中心距215 mm，水平旋转−6.4°；未缩小。")
                } else {
                    ContextHelp(
                        "内侧270°保留衣架卷芯，外圈缩小。沿用Ø21.3 mm管与原定位件；卷芯设定内径29.7 mm，双墙净隙3 mm。中心距可调120–230 mm；默认150 mm，原版为230 mm。")
                }
                ContextHelp("首层等高闭合，墙体连续升Z，顶部整平。管与固定套另行装配，不作为主体打印；调整高度不改变插管接口。")
            } else if doubleScroll {
                Picker(L("轮廓样式"), selection: model.binding("DoubleProfile")) {
                    uiText("镜像双卷").tag("0")
                    uiText("S 形双卷长灯").tag("1")
                    uiText("圆弧深卷（对称）").tag("2")
                    uiText("等距双螺旋（平顺）").tag("3")
                }.pickerStyle(.menu)
                Picker(L("走线方式"), selection: model.binding("DoubleLines")) {
                    uiText("单线开放").tag("1")
                    uiText("双线闭合").tag("2")
                    uiText("花瓶模式（连续升 Z）").tag("3")
                }.pickerStyle(.menu)
                if ["2", "3"].contains(model.fields["DoubleLines"] ?? "1") {
                    row("双线净间隙", "DoubleLaneGap")
                    uiText("一侧绕入，中心圆弧回转，沿另一侧绕出；两瓣连成闭合轮廓。净间隙不包含两侧料道的宽度。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                }
                if doubleVase {
                    ContextHelp("首层等高走完整个闭合轮廓，随后同向连续升 Z。层高为每周最大上升量，自动均分到完整周；顶部按剩余间隙整平。")
                    uiText("花瓶模式使用等距双螺旋；需要为两侧料道及内卷回转留出空间。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                row(["2", "3"].contains(model.fields["DoubleProfile"] ?? "0") ? "参考圆外径" : "单瓣外径", "DoubleD")
                row("每侧螺旋圈数", "DoubleTurns", "圈")
                row(["2", "3"].contains(model.fields["DoubleProfile"] ?? "0") ? "两圆参考外缘间距" : "两螺旋外缘间距", "DoubleGap")
                row(model.fields["DoubleProfile"] != "0" ? "灯体长度（打印高度）" : "总高度", "DoubleHeight")
                row("平面旋转", "DoubleRot", "°")
                if model.fields["DoubleProfile"] == "3" {
                    ContextHelp(
                        "两侧为等距阿基米德螺旋，支持 1–4 圈及小数；严格旋转对称。调整间距会重新求解平顺过渡，保持连接处方向和曲率连续。",
                        "参考间距按含线宽的两参考圆计算，不是螺旋线之间的最短距离。间距过大或料道过密时，切片会提示调整。"
                    )
                } else if model.fields["DoubleProfile"] == "2" {
                    ContextHelp("两侧各含 270° 正圆主弧，内圈渐收；两瓣严格旋转对称，连接处弯曲连续。间距按含线宽的两个参考圆计算。")
                } else {
                    ContextHelp("左右圈数同步，支持 1–4 圈及小数。间距按两瓣相向外缘的净距计算；调整间距只伸缩中间连接段。")
                }
                if model.fields["DoubleProfile"] != "0" {
                    ContextHelp("端面为连续 S 形双卷；灯体长度沿 Z 方向延伸，调整长度不改变端面。打印时长轴竖直，横放后成为长条灯罩。")
                }
                uiText("单瓣外径包含线宽。圈数按每侧单程绕入计算，回程不重复计数；造型预览尚未验证座具承重。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if vase {
                row("路径外接直径", "VaseD")
                row("总高度", "VaseHeight")
                row("每瓣螺旋圈数", "VaseTurns", "圈")
                row("最小空腔直径", "VaseCoreDiameter")
                row("平面旋转", "TripleRot", "°")
                uiText("每瓣圈数支持 1–6 圈，可输入 2.5 等小数。减少圈数可留出更多空间；上下截面一致。").interfaceFont(.caption).foregroundColor(
                    .secondary)
                ContextHelp("空腔直径为扣除线宽后的最小净空；减少圈数后自然变大的空腔会保留。外接直径按路径中心线计算，不含材料宽度。")
                uiText("完整三瓣实心底在「底部」调整；切片时检查相邻料道间距。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if triple {
                row("路径外接直径", "TripleD")
                row("长螺旋圈数", "TripleTurns", "圈")
                row("总高度", "TripleHeight")
                row("平面旋转", "TripleRot", "°")
                uiText("原脚本的三个阿基米德螺旋，连接成一条闭合路径。直径指路径中心线外接圆，不包含材料宽度。").interfaceFont(.caption).foregroundColor(
                    .secondary)
            } else if model.fields["SourceMode"] == "Crescent" {
                row("外径", "CrescentD")
                row("总高度", "CrescentHeight")
                row("月牙最厚处", "CrescentThickness")
                row("开口净宽", "CrescentGap")
                row("开口方向", "CrescentRotation", "°")
                row("灯泡参考直径", "CrescentBulbD")
                uiText("一个深弯月围成灯罩，两端圆滑。灯泡虚线固定在外圆正中心，仅供定位，不参与打印。").interfaceFont(.caption).foregroundColor(.secondary)
                uiText("沿月牙边界打印空心壳体；不整块填实，不生成底盘或灯座。开口方向 0° 朝右。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if model.fields["SourceMode"] == "Ellipse" {
                row("长轴外径", "EllipseMajor")
                row("短轴外径", "EllipseMinor")
                row("总高度", "EllipseHeight")
                row("平面旋转", "EllipseRotation", "°")
                uiText("两轴为完整外径，不是半径。上下截面一致；长短轴相等时为圆柱。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if cone {
                row("下口外径", "ConeBottomD")
                row("上口外径", "ConeTopD")
                row("总高度", "ConeHeight")
                ContextHelp("开口锥形 / 圆台灯罩，上下口径均需大于线宽；不收尖封顶。")
            } else {
                row("外径", "Dout")
                row("总高度", "CH")
                if nonplanar {
                    row("口沿下凹深度", "NPDepth")
                    row("起伏开始高度", "NPStart")
                    row("下凹方向", "NPDirection", "°")
                    uiText("两高两低，保持中间开口。总高度为口沿最高点；下凹深度为最高点与最低点的高度差。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                    uiText("已配套非平面走线：从起伏开始高度逐渐变形。方向 0° 为左右下凹，90° 为前后下凹。").interfaceFont(.caption).foregroundColor(
                        .secondary)
                    uiText("实验样品：喷嘴保持竖直，未校验打印头碰撞；先检查喷嘴周围的避让空间。").interfaceFont(.caption).foregroundColor(.secondary)
                }
            }
            if !travelTest {
                if fern {
                    ContextHelp("线宽固定8 mm；主体与首层层高最大3.5 mm。首层等高、主体连续升Z，顶部整平；不生成实心底或叠加效果。")
                } else if wardrobe {
                    if !model.toggle("WardBedTest").wrappedValue {
                        ContextHelp("闭合双墙连续升 Z；横梁与开孔段分开打印，分件顶部连续整平。逐层几何补偿在 EF 页设置；无实心底，不叠加波形。请先打印短段校核孔径与回转成形。")
                    }
                } else if egg {
                    uiText("闭合双线连续升 Z，无整片底面；EF 与波形不参与，线宽按实际毫米数校核。").interfaceFont(.caption).foregroundColor(.secondary)
                } else if pipeScroll {
                    uiText("双墙连续升Z；不封插管孔，EF及叠加波形不参与。").interfaceFont(.caption).foregroundColor(.secondary)
                } else if corner {
                    uiText("贯通无底模块；EF、首层外缘校准与波形不参与。先用短段检查连接管插配。").interfaceFont(.caption).foregroundColor(.secondary)
                } else if bud {
                    ContextHelp("当前为无底花蕾模块，不生成立柱实体；EF 与首层外缘校准不参与。颗粒成形及喷嘴避让仍需试样验证。")
                } else if doubleScroll {
                    uiText("当前为卷曲墙体，不含整片底面；闭合走线支持 EF，首层外缘校准不参与。").interfaceFont(.caption).foregroundColor(.secondary)
                } else if model.fields["SourceMode"] == "Crescent" {
                    uiText("当前为卷曲墙体，不含整片底面或坐面；EF 和首层外缘校准不参与。").interfaceFont(.caption).foregroundColor(.secondary)
                } else if triple {
                    ContextHelp("沿整个三螺旋闭合路径走一遍，上升一个层高。先在首层高度走一整周，再按弧长连续上升；本版无底，不应用 EF。")
                    DisclosureGroup(L("采样精度")) { row("每转采样数", "TriplePts", "点") }
                } else {
                    Divider()
                    if model.toggle("AlignLeft").wrappedValue {
                        Label(
                            L("接缝固定在左侧 · 打印中可关闭"),
                            systemImage: "arrow.left.to.line"
                        ).interfaceFont(.caption).foregroundColor(.secondary)
                    } else {
                        row("接缝角度", "SeamAngle", "°")
                    }
                }
            }
        }
    }
}
