import SwiftUI

struct PrintQualityControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    private var heightHelp:String {
        let mode=model.fields["SourceMode"] ?? ""
        if mode=="Wardrobe",model.toggle("WardBedTest").wrappedValue {return "等高测试按所设层高叠加；连续测试沿用正式底梁实际圈距，总高在切片结果中显示。"}
        if ["PipeScroll","SingleBud","CornerPipe","EggScroll","Wardrobe"].contains(mode) || (mode=="DoubleScroll" && model.fields["DoubleLines"]=="3") {return "花瓶模式中层高为每周最大上升量；首层仍为等高闭合走线。"}
        if ["DoubleScroll","Crescent"].contains(mode) {return "每层等高打印，抬 Z 换层；单线沿原路往返，双线走完整个闭合轮廓。"}
        if mode=="NonplanarCylinder" {return "层高为变形前每圈的上升量；变形后按相邻圈实际间隙调整挤出。"}
        return "螺旋模式中，层高是路径每完整一圈的上升量。"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            uiText("线宽与层高").interfaceFont(.headline)
            if model.fields["SourceMode"]=="TravelTest" {
                StaticNumberRow(label:"外墙线宽",value:"8")
                StaticNumberRow(label:"层高",value:"3.5")
            } else {
            NumberRow(model:model,label:"外墙线宽",key:"W")
                .disabled(["Fern1060","Fern1060E","PipeScroll"].contains(model.fields["SourceMode"] ?? ""))
            NumberRow(model:model,label:"层高",key:model.fields["SourceMode"]=="Triple" ? "TriplePitch":"H")
                .help(L(heightHelp))
            }
            Divider()
        }
    }
}

struct StaticNumberRow:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    let label:String
    let value:String
    var unit="mm"
    var body:some View {
        HStack(spacing:8) {
            uiText(label).frame(maxWidth:.infinity,alignment:.leading)
            Text(value).monospacedDigit().frame(width:84,alignment:.trailing)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width:38,alignment:.leading)
        }.frame(minHeight:30)
    }
}

struct DeviceMenuItems:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        Button {if model.isBambu {model.openBambuConnect()}else{openWindow(id:"printer")}} label:{
            Label {uiText(model.isBambu ? "打开 Bambu Connect":"打印机控制")} icon:{Image(nsImage:FabricationSymbol.image)}
        }
        Button {openWindow(id:"camera-monitor")} label:{Label(L("打印监控"),systemImage:"video")}
        Divider()
        Button {openWindow(id:"pellet-dryer")} label:{Label {uiText("颗粒烘干机")} icon:{Image(nsImage:DryerSymbol.pellet)}}
        Button {openWindow(id:"ams-ht")} label:{Label {uiText("AMS-HT 烘干机")} icon:{Image(nsImage:DryerSymbol.ams)}}
    }
}

struct DeviceToolbarButtons:View {
    @ObservedObject var model:Workbench
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        Button {if model.isBambu {model.openBambuConnect()}else{openWindow(id:"printer")}} label:{
            Label {Text("打印机控制")} icon:{Image(nsImage:FabricationSymbol.image)}
        }.help(model.isBambu ? "打印机控制 · 打开 Bambu Connect":"打印机控制").accessibilityLabel("打印机控制")
        Button {openWindow(id:"camera-monitor")} label:{Label("打印监控",systemImage:"video")}
            .help("打印监控").accessibilityLabel("打印监控")
        Button {openWindow(id:"pellet-dryer")} label:{Label {Text("颗粒烘干机")} icon:{Image(nsImage:DryerSymbol.pellet)}}
            .help("颗粒烘干机").accessibilityLabel("颗粒烘干机")
        Button {openWindow(id:"ams-ht")} label:{Label {Text("AMS-HT 烘干机")} icon:{Image(nsImage:DryerSymbol.ams)}}
            .help("AMS-HT 烘干机").accessibilityLabel("AMS-HT 烘干机")
    }
}

struct WorkspaceCommands:Commands {
    @FocusedObject private var model:Workbench?
    @ObservedObject private var language=AppLanguage.shared
    var body:some Commands {
        CommandGroup(after:.toolbar) {
            if let model=model {
                Divider()
                Picker(L("工作区"),selection:Binding(get:{model.calibrationActive},set:{model.calibrationActive=$0})) {
                    uiText("建模").tag(false);uiText("校准").tag(true)
                }
                if !model.calibrationActive {
                    Menu(L("参数")) {
                        Picker("",selection:Binding(get:{model.parameterTab},set:{model.parameterTab=$0})) {
                            uiText("造型").tag(0);uiText("底部").tag(4);uiText("补偿").tag(2);uiText("打印").tag(3)
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    Menu(L("预览")) {
                        Toggle(L("模型"),isOn:Binding(get:{model.showingModel},set:{if $0 {model.showingModel=true}}))
                        Toggle(L("切片结果"),isOn:Binding(get:{!model.showingModel},set:{if $0,model.preview != nil {model.showingModel=false}})).disabled(model.preview==nil)
                    }
                    Menu(L("视角")) {
                        Button(L("立体视角")){model.cameraAction(5)}
                        Button(L("俯视")){model.cameraAction(1)}
                        Button(L("正视")){model.cameraAction(3)}
                        Button(L("左视")){model.cameraAction(4)}
                        Divider()
                        Toggle(L("平移模式"),isOn:Binding(get:{model.panMode},set:{model.panMode=$0}))
                        Button(L("复位")){model.cameraAction(0)}
                        Button(L("适合窗口")){model.cameraAction(2)}
                        if !model.showingModel {Button(L("查看整个平台")){model.cameraAction(6)}}
                    }
                    if !model.showingModel {
                        Picker(L("显示模式"),selection:Binding(get:{model.previewMode},set:{model.previewMode=$0})) {ForEach(PreviewMode.allCases){uiText($0.rawValue).tag($0)}}
                        Toggle(L("料道"),isOn:Binding(get:{model.showBeads},set:{model.showBeads=$0}))
                        Toggle(L("空移"),isOn:Binding(get:{model.showTravel},set:{model.showTravel=$0}))
                        Toggle(L("打印平台"),isOn:Binding(get:{model.showBed},set:{model.showBed=$0}))
                    }
                }
            }
        }
        CommandMenu(L("切片")) {
            Button(L("切片")){model?.generate()}.keyboardShortcut("r").disabled(model?.canSlice != true)
            Button(L(model?.sendTitle ?? "发送…")){model?.requestSend()}.disabled(model?.canSend != true)
        }
        CommandMenu(L("设备")) {
            if let model=model {DeviceMenuItems(model:model)}
        }
    }
}

struct PresetHeader<Actions:View>:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    let title:String
    let actions:()->Actions
    init(_ title:String,@ViewBuilder actions:@escaping()->Actions) {self.title=title;self.actions=actions}
    var body:some View {
        HStack {
            uiText(title).interfaceFont(.headline)
            Spacer()
            Menu {actions()} label:{Label(L("管理预设"),systemImage:"ellipsis.circle").labelStyle(.iconOnly)}
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("管理预设"))
        }
    }
}

extension Workbench {
    var hasActiveEffects:Bool {["NoiseEnabled","WaveEnabled","MeshEnabled"].contains{toggle($0).wrappedValue}}
    var supportsEffects:Bool {["Cylinder","Ellipse","Cone","Triple"].contains(fields["SourceMode"] ?? "")}
    var supportsCompensation:Bool {
        let mode=fields["SourceMode"] ?? ""
        return !["Triple","TripleVase","Crescent","SingleBud","CornerPipe","EggScroll","TravelTest","Fern1060","Fern1060E","PipeScroll","PelletBottle"].contains(mode) && !(mode=="DoubleScroll" && fields["DoubleLines"]=="1")
    }
}
