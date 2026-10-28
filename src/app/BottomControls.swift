import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Workbench {
    var bottomSelection:Binding<String> {
        Binding(get:{self.toggle("HasBottom").wrappedValue ? (self.fields["BottomKind"] ?? "Annular"):"None"},set:{value in
            self.fields["HasBottom"]=value=="None" ? "0":"1"
            if value != "None" {self.fields["BottomKind"]=value}
            if value=="Annular" && self.fields["BottomPattern"]=="Zigzag" {self.fields["BottomPattern"]="Monotonic"}
            self.dirty=true
        })
    }
    func importModel() {
        guard canImport else{return}
        let panel=NSOpenPanel();panel.title=L("导入模型");panel.allowsMultipleSelection=false
        panel.allowedContentTypes=["stl","obj","step","stp"].compactMap{UTType(filenameExtension:$0)}
        guard panel.runModal()==NSApplication.ModalResponse.OK,let url=panel.url else{return}
        importModel(url)
    }
    func importModel(_ url:URL) {
        guard canImport else{return}
        rememberShape()
        guard url.isFileURL,["stl","obj","step","stp"].contains(url.pathExtension.lowercased()) else {error=L("请拖入单个 STL、OBJ 或 STEP 模型文件。");return}
        var isDirectory:ObjCBool=false
        guard FileManager.default.fileExists(atPath:url.path,isDirectory:&isDirectory),!isDirectory.boolValue else {error=L("模型文件不存在，请重新选择。");return}
        fields["ImportFile"]=url.path;fields["SourceMode"]="Imported";dirty=true;preview=nil;gcodeURL=nil;savedURL=nil
        status="已选择 \(url.lastPathComponent)，正在更新预览。"
    }
    func receiveModelDrop(_ providers:[NSItemProvider])->Bool {
        guard canImport else{return false}
        guard providers.count==1,let provider=providers.first,provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            error=L("请拖入单个 STL、OBJ 或 STEP 模型文件。");return false
        }
        provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) {item,failure in
            let url:URL?
            if let data=item as? Data {url=URL(dataRepresentation:data,relativeTo:nil)}
            else if let value=item as? URL {url=value}
            else {url=nil}
            DispatchQueue.main.async {
                guard let url=url,failure==nil else {self.error=L("无法读取拖入的模型文件。");return}
                self.importModel(url)
            }
        }
        return true
    }
}

struct WardrobeBedTestControls:View {
    @ObservedObject var model:Workbench
    var body:some View {
        Toggle(L("整件底部少层测试"),isOn:model.toggle("WardBedTest"))
        if model.toggle("WardBedTest").wrappedValue {
            Picker(L("测试层数"),selection:model.binding("WardTestLayers")) {
                uiText("2 层").tag("2")
                uiText("3 层").tag("3")
            }.pickerStyle(.menu)
            Toggle(L("连续升 Z（与正式件一致）"),isOn:model.toggle("WardTestContinuous"))
            Text(model.toggle("WardTestContinuous").wrappedValue ? "首层等高，其后连续升 Z，沿用正式底梁实际圈距和 EF 过渡。最后一圈结束即停止，不额外填平顶部。":"各层等高打印，换层时抬 Z；EF 仅作用于首层。").interfaceFont(.caption).foregroundColor(.secondary)
            ContextHelp("保留完整①底梁尺寸；打印所选层数后结束。用料与时间只统计本次测试，关闭后恢复选定的正式分件。")
        }
    }
}

struct SkirtControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            uiText("首层准备 · 裙边").interfaceFont(.headline)
            if ["Fern1060","Fern1060E"].contains(model.fields["SourceMode"] ?? "") {
                uiText("此造型不使用外围裙边").foregroundStyle(.secondary)
            } else if model.fields["SourceMode"]=="TravelTest" {
                Toggle(L("启用裙边"),isOn:.constant(true)).disabled(true)
            } else {Toggle(L("启用裙边"),isOn:model.toggle("SKIRT_AUTO"))}
            if (model.toggle("SKIRT_AUTO").wrappedValue || model.fields["SourceMode"]=="TravelTest") && !["Fern1060","Fern1060E"].contains(model.fields["SourceMode"] ?? "") {
                NumberRow(model:model,label:"裙边净距离",key:"SKIRT_GAP",unit:"mm")
                if model.fields["SourceMode"]=="TravelTest" {
                    StaticNumberRow(label:"裙边速度",value:"9",unit:"mm/s")
                }else{NumberRow(model:model,label:"裙边速度",key:"SKIRT_F",unit:"mm/s")}
            }
            ContextHelp("首层先沿模型外围打印一圈独立裙边，再进入主体。裙边沿用首层层高、线宽与首层流量；用于预出料和检查占地，不与主体相连。")
        }
    }
}

struct BottomControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    func row(_ label:String,_ key:String,_ unit:String="mm")->some View {NumberRow(model:model,label:label,key:key,unit:unit)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            uiText("底部设计").interfaceFont(.headline)
            if model.fields["SourceMode"]=="TravelTest" {
                uiText("跨孔测试不生成实心底。").foregroundStyle(.secondary)
            } else if model.fields["SourceMode"]=="Hopper" {
                ContextHelp("此料桶上下贯通，不封底。大口贴平台打印首圈，再连续螺旋上升至小嘴；下端194.7 mm固定。")
            } else if model.fields["SourceMode"]=="PelletBottle" {
                uiText("料瓶固定使用实心封底；瓶身与收口为单墙连续螺旋。首层高度在底部页设置。").interfaceFont(.caption).foregroundColor(.secondary)
                row("封底层数","B","层")
                row("其余底层层高","BH")
                row("底部线宽","WB")
                ContextHelp("默认2层 × 3.5 mm，共7 mm。两层交错填充，实际封闭性需试印确认。EF和首层外缘补偿不参与此造型。")
            } else if ["Fern1060","Fern1060E"].contains(model.fields["SourceMode"] ?? "") {
                ContextHelp("圆拱支架沿进深连续升Z；首层为闭合轮廓，不封中央开口。打印高度在造型页调整。外围裙边关闭；内部清料圈尚未加入。")
            } else if model.fields["SourceMode"]=="Wardrobe" {
                WardrobeBedTestControls(model:model)
                ContextHelp("挂衣体每件为闭合双墙连续路径，不封底。上下件分别打印；上件在安装时翻转。裙边属于打印准备，不计入单件连续造型路径。")
            } else if model.fields["SourceMode"]=="PipeScroll" {
                ContextHelp("插管型保留贯通卷芯，不生成实心底。首层等高闭合，随后连续升Z；总高度在造型页，首层层高在底部页设置。")
            } else if model.fields["SourceMode"]=="EggScroll" {
                uiText("蛋形双卷沿进深连续升 Z，不封闭中央留空。整体高度在造型页调整；进深自动按比例生成。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if model.fields["SourceMode"]=="CornerPipe" {
                uiText("当前为贯通管孔模块，不生成整片底面；EF 与首层外缘校准不参与。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if model.fields["SourceMode"]=="SingleBud" {
                uiText("单螺旋花蕾保留裙边与首层等高闭合路径，随后连续升 Z；不生成实心底或立柱。首层层高在底部页调整。").interfaceFont(.callout).foregroundColor(.secondary)
            } else if model.fields["SourceMode"]=="Crescent" {
                uiText("单弯月灯罩当前生成空心壳体，不生成底盘或灯座。灯泡参考固定在外圆中心。").interfaceFont(.callout).foregroundColor(.secondary)
            } else if model.fields["SourceMode"]=="DoubleScroll" {
                uiText(model.fields["DoubleLines"] == "3" ? "花瓶模式保留自动裙边和首层等高闭合走线；随后墙体连续升 Z，不生成整片实心底。裙边与首层层高在本页设置。":"双螺旋当前不生成整片底面或坐面。单线／双线、圈数和间距在「造型」中调整。").interfaceFont(.callout).foregroundColor(.secondary)
            } else if model.fields["SourceMode"]=="Triple" {
                uiText("三螺旋路径暂不生成底部，请选择圆柱、锥形或导入模型。").interfaceFont(.callout).foregroundColor(.secondary)
            } else if model.fields["SourceMode"]=="TripleVase" {
                uiText("完整三瓣实心底").interfaceFont(.subheadline)
                uiText("沿三瓣最外轮廓整片封底，中心孔和螺旋间隙均填满。").interfaceFont(.caption).foregroundColor(.secondary)
                row("底部层数","VaseBaseLayers","层")
                row("底部层高","BH")
                row("填充线宽","WB")
                Divider()
                uiText("连续折线").interfaceFont(.subheadline)
                uiText("相邻填充线尽量连续出料；跨出底面或连接过长的位置保留回抽空移，每层最后打印完整外轮廓。").interfaceFont(.caption).foregroundColor(.secondary)
                BottomDirectionControls(model:model)
                uiText("几何封底后仍需实物静置试水，检查底面和层间是否渗漏。").interfaceFont(.caption).foregroundColor(.secondary)
            } else {
                Picker(L("底部类型"),selection:model.bottomSelection) {
                    uiText("无底").tag("None")
                    uiText("环形底").tag("Annular")
                    uiText("实心底").tag("Solid")
                }.id(appLanguage.code)
                if model.toggle("HasBottom").wrappedValue {
                    if model.fields["BottomKind"] != "Solid" {row("内孔直径","Din")}
                    row("底部层数","B","层")
                        row("底部层高","BH")
                    row("填充线宽","WB")
                    Picker(L("填充图案"),selection:model.binding("BottomPattern")) {
                        uiText("螺旋").tag("Spiral")
                        uiText("平行直线").tag("Monotonic")
                        if model.fields["BottomKind"]=="Solid" {uiText("连续折线").tag("Zigzag")}
                    }.id(appLanguage.code)
                    if ["Monotonic","Zigzag"].contains(model.fields["BottomPattern"] ?? "") {
                        BottomDirectionControls(model:model)
                        ContextHelp(model.fields["BottomPattern"]=="Zigzag" ? "相邻填充线尽量连续出料；跨出底面或连接过长的位置保留回抽空移，每层最后打印完整外轮廓。":"按顺序铺设平行线，分段之间回抽抬升；每层最后打印完整外轮廓，再接入墙体。")
                    } else {
                        ContextHelp("连续螺旋填充；多层底交替向内、向外，换层直接抬 Z。")
                    }
                } else {
                    uiText("仅打印一圈平面墙脚，随后连续螺旋上升。").interfaceFont(.caption).foregroundColor(.secondary)
                }
            }
            Divider()
            uiText("首层").interfaceFont(.headline)
            if model.fields["SourceMode"]=="TravelTest" {StaticNumberRow(label:"首层层高",value:"2.5")}
            else {row("首层层高","H0")}
            row("首层流量比例","F0","×")
            Divider()
            SkirtControls(model:model)
        }
    }
}

struct EdgeCalibrationControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    func row(_ label:String,_ key:String)->some View {NumberRow(model:model,label:label,key:key)}
    private var edgeEligible:Bool {
        (model.fields["PrinterModel"] ?? "G1")=="G1" &&
        ["Cylinder","Cone"].contains(model.fields["SourceMode"] ?? "") &&
        model.toggle("HasBottom").wrappedValue && model.fields["BottomKind"]=="Annular" &&
        model.fields["BottomPattern"]=="Spiral" &&
        Double(model.fields["B"] ?? "")==1 && model.toggle("AlignLeft").wrappedValue
    }
    var body:some View {
        if (model.fields["PrinterModel"] ?? "G1")=="G1",["Cylinder","Cone"].contains(model.fields["SourceMode"] ?? "") {
            Divider()
                    Toggle(L("首层外缘校准"),isOn:model.toggle("EdgeCalibrationEnabled")).disabled(!edgeEligible)
                    if edgeEligible {
                        if model.toggle("EdgeCalibrationEnabled").wrappedValue {
                            row("外凸处最大内收","EdgeBulgeIn")
                            row("内缩处最大外补","EdgeDipOut")
                            ContextHelp(
                                "180° 开始内收，270° 最大，330° 回到 0。330° 后向外补，0° 最大，20° 回到 0。",
                                "右 0° · 上 90° · 左 180° · 下 270°。20°–180° 暂不修正；跨圈处自动识别外缘料道。"
                            )
                            Button(L("恢复本次实测值")) {
                                model.fields["EdgeBulgeIn"]="1.5";model.fields["EdgeDipOut"]="0.5";model.dirty=true
                            }
                            ContextHelp("叠加在 EF 之后，保持 Z 和单位长度挤出量。修改流量、起点或填充参数后，需要重新验证这组实测校准。")
                        }
                    } else {
                        uiText("仅适用于 G1、单层环形螺旋底、圆柱或锥形，并启用左侧接缝。当前条件不满足，校准不生效。").interfaceFont(.caption).foregroundColor(.secondary)
                    }
        }
    }
}

struct BottomDirectionControls:View {
    @ObservedObject var model:Workbench
    @State private var editingCustom=false
    private var direction:String {
        if editingCustom || !(model.fields["FillAngles"] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return "custom"}
        let step=Double(model.fields["FillAngleStep"] ?? "90") ?? .nan
        return step==90 ? "cross":step==0 ? "same":"custom"
    }
    var body:some View {
        Picker("填充方向",selection:Binding(get:{direction},set:{value in
            editingCustom=value=="custom"
            if value != "custom" {model.setBottomDirection(value)}
        })) {
            Text("各层交叉").tag("cross")
            Text("各层同向").tag("same")
            Text("自定义").tag("custom")
        }
        if direction=="custom" {
            NumberRow(model:model,label:"起始方向",key:"FillAngle",unit:"°")
            NumberRow(model:model,label:"每层旋转",key:"FillAngleStep",unit:"°")
            DisclosureGroup("指定个别层") {
                TextEditor(text:model.binding("FillAngles")).font(.system(.body,design:.monospaced)).frame(height:120).padding(6).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8))
                ContextHelp("每行「层号:角度」，例如 1:45、2:90。第一层从 1 开始；未填写的层使用起始角度与逐层旋转。")
            }
        }
    }
}
extension Workbench {
    func setBottomDirection(_ direction:String) {
        guard ["cross","same"].contains(direction) else{return}
        fields["FillAngleStep"]=direction=="cross" ? "90":"0"
        fields["FillAngles"]="";dirty=true
    }
}
