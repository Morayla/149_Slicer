import SwiftUI
import AppKit

extension Workbench {
    var printerModel:String {fields["PrinterModel"] ?? "G1"}
    var isBambu:Bool {printerModel != "G1"}
    var printerSelection:Binding<String> {Binding(get:{self.printerModel},set:{self.selectPrinter($0)})}
    var nozzleSelection:Binding<String> {Binding(get:{self.fields["Nozzle"] ?? "0.4"},set:{value in
        self.fields["Nozzle"]=value
        let n=Double(value) ?? 0.4
        for (k,v) in ["W":n*1.125,"WB":n*1.125,"H":n/2,"BH":n/2,"H0":n/2,"InnerStartW":n,"TriplePitch":n/2] {self.fields[k]=String(format:"%.4g",v)}
        self.dirty=true
    })}
    func selectPrinter(_ next:String) {
        guard next != printerModel,!busy else{return}
        rememberShape()
        let store=preferences
        store.set(fields,forKey:"149.machine.fields."+printerModel)
        if let cached=store.dictionary(forKey:"149.machine.fields."+next) as? [String:String] {
            fields.merge(cached,uniquingKeysWith:{$1})
        } else if next != "G1" {
            // A fresh machine gets a small lamp and filament settings. Returning
            // to another machine restores its entire draft, including its EF.
            let center=next=="H2D" ? (162.5,160.0):next=="A1 mini" ? (90.0,90.0):(128.0,128.0)
            let preset:[String:String]=["SourceMode":"Cylinder","Dout":"60","Din":"20","CH":"40","ConeBottomD":"60","ConeTopD":"40","ConeHeight":"40","TripleD":"60","TripleHeight":"10","TriplePitch":"0.2","N":"0","Tolerance":"0.02","W":"0.45","WB":"0.45","H":"0.2","BH":"0.2","H0":"0.2","Nozzle":"0.4","H2DNozzle":"Left","B":"1","HasBottom":"0","EF":"0.15","EFLayers":"3","EFTable":"0:100\n1:65\n2:25\n3:0","EFEnabled":"0","InnerStartW":"0.4","WaveEnabled":"0","WaveAmp":"0.5","WaveNegAmp":"0","FilamentType":"PETG","FilamentDiameter":"1.75","MaxVolumetric":"8","BBRetraction":"0.8","BBRetractionSpeed":"30","BBTravel":"100","BBHop":"0.4","BBFan":"40","NT":"245","BT":"70","FM":"1","F0":"1","PF":"1","BottomF":"20","WallF":"30","SKIRT_F":"20","SKIRT_GAP":"3","FinishLength":"5","Finish":"1","BuildPlate":"Textured PEI Plate","Density":"1.27","ExtraWasteG":"0","CX":String(center.0),"CY":String(center.1)]
            fields.merge(preset,uniquingKeysWith:{$1})
        }
        fields["PrinterModel"]=next;store.set(fields,forKey:"149.machine.fields."+next);store.set(next,forKey:"149.lastPrinter");preview=nil;dirty=true;savedURL=nil
        status="已切换机型，请核对材料和喷嘴后切片。"
    }
    func openBambuConnect() {
        if let app=NSWorkspace.shared.urlForApplication(toOpen:URL(string:"bambu-connect://import-file")!) {NSWorkspace.shared.open(app)}
        else {self.error=L("尚未安装 Bambu Connect。请在打印设置中打开官方安装页面。")}
    }
    func sendToBambu() {
        guard isBambu,!dirty,!busy,let raw=gcodeURL else{return}
        let source=URL(fileURLWithPath:raw.path+".3mf")
        var link=URLComponents();link.scheme="bambu-connect";link.host="import-file"
        do {
            // Stable local copy survives a new preview, project switch or quit.
            let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("149/Transfers")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let name="149_"+printerModel.replacingOccurrences(of:" ",with:"_")+"_"+UUID().uuidString.prefix(8)+".gcode.3mf"
            let target=dir.appendingPathComponent(name)
            try Data(contentsOf:source).write(to:target,options:.atomic)
            link.queryItems=[URLQueryItem(name:"path",value:target.path),URLQueryItem(name:"name",value:name),URLQueryItem(name:"version",value:"1.1.0")]
            guard let url=link.url else {throw message("无法构建 Bambu Connect 链接。")}
            guard NSWorkspace.shared.urlForApplication(toOpen:url) != nil else {
                NSWorkspace.shared.activateFileViewerSelecting([target])
                throw message("尚未安装 Bambu Connect。文件已准备好，可先安装官方软件，再点击发送。")
            }
            guard NSWorkspace.shared.open(url) else {throw message("Bambu Connect 未能打开，请检查安装。")}
            savedURL=target;status="已交给 Bambu Connect，请在官方窗口确认打印机和耗材。"
        } catch {self.error=error.localizedDescription}
    }
}

struct PrinterSelector:View {
    @ObservedObject var model:Workbench
    @ObservedObject private var language=AppLanguage.shared
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:8) {
            FabricationIcon()
            Picker(L("打印机"),selection:model.printerSelection) {
                Text("Ginger G1").tag("G1")
                ForEach(["H2D","P1P","A1","A1 mini"],id:\.self) {Text("Bambu Lab "+$0).tag($0)}
            }
            }
            if model.isBambu {
                Picker(L("喷嘴直径"),selection:model.nozzleSelection) {
                    ForEach(["0.4","0.6","0.8"],id:\.self) {Text($0+" mm").tag($0)}
                }
                if model.printerModel=="H2D" {
                    Picker(L("打印喷嘴"),selection:model.binding("H2DNozzle")) {
                        uiText("左喷嘴").tag("Left")
                        uiText("右喷嘴").tag("Right")
                    }
                    uiText(model.fields["H2DNozzle"]=="Right" ? "右喷嘴范围：X 25–350 · Y 0–320 mm" : "左喷嘴范围：X 0–325 · Y 0–320 mm").interfaceFont(.caption).foregroundColor(.secondary)
                    uiText("单喷嘴打印 · 直径须与所选喷嘴一致").interfaceFont(.caption).foregroundColor(.secondary)
                }
            }
        }.disabled(model.busy)
    }
}

struct BambuControls:View {
    @ObservedObject var model:Workbench
    @ObservedObject private var language=AppLanguage.shared
    func row(_ label:String,_ key:String,_ unit:String="mm")->some View {NumberRow(model:model,label:label,key:key,unit:unit)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if model.printerModel=="H2D" {
                Picker(L("启动方式"),selection:model.binding("H2DStartup")) {
                    uiText("官方完整启动").tag("Official")
                    uiText("简化启动（已装料）").tag("Simple")
                }
                if model.fields["H2DStartup"]=="Simple" {
                    uiText("先装好所选喷嘴的耗材。归零、抬升并等待温度后开始；不额外冲刷、动态流量校准或重新调平。").interfaceFont(.caption).foregroundColor(.secondary)
                    uiText("喷嘴选择仍由机器执行；未装好料时可能触发换料。结束仍使用官方退料流程。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                Divider()
            }
            uiText("材料与温度").interfaceFont(.headline)
            Picker(L("材料类型"),selection:model.binding("FilamentType")) {ForEach(["PLA","PETG","TPU"],id:\.self) {Text($0).tag($0)}}
            uiText("材料类型用于官方启动流程；温度、流量和风扇请按实际丝材设置。").interfaceFont(.caption).foregroundColor(.secondary)
            row("喷嘴温度","NT","°C");row("热床温度","BT","°C")
            Picker(L("打印板"),selection:model.binding("BuildPlate")) {
                uiText("纹理 PEI 板").tag("Textured PEI Plate");uiText("光面高温板").tag("High Temp Plate")
            }
            Divider();uiText("流量与速度").interfaceFont(.headline)
            row("流量比例","FM","×");
            row("最大体积流量","MaxVolumetric","mm³/s")
            FilamentFlowAssessment(model:model)
            row("底部填充速度","BottomF","mm/s");row("外墙速度","WallF","mm/s")
            row("空移速度","BBTravel","mm/s");row("冷却风扇","BBFan","%")
            uiText("首层关闭风扇，后续使用设定值；超过最大体积流量时自动降低路径速度。").interfaceFont(.caption).foregroundColor(.secondary)
            Divider();uiText("回抽与抬升").interfaceFont(.headline)
            row("回抽长度","BBRetraction");row("回抽速度","BBRetractionSpeed","mm/s");row("回抽时抬升 Z","BBHop")
            Divider();uiText("平台与收尾").interfaceFont(.headline)
            row("模型中心 X","CX");row("模型中心 Y","CY")
            Toggle(L("左侧对齐裙边、首层与收尾"),isOn:model.toggle("AlignLeft"))
            Toggle(L("顶部减流收尾"),isOn:model.toggle("Finish"))
            if model.toggle("Finish").wrappedValue {
                row("收尾流量比例","FinishFlow","×")
                if model.fields["SourceMode"] == "NonplanarCylinder" {uiText("沿完整起伏口沿逐渐减流，不叠加末段二次减流。").interfaceFont(.caption).foregroundColor(.secondary)}
                else if model.toggle("WaveEnabled").wrappedValue || model.toggle("MeshEnabled").wrappedValue || ["DoubleScroll","Crescent"].contains(model.fields["SourceMode"] ?? "") {row("波形末段收尾长度","FinishLength")}
            }
            Divider();uiText("材料用量").interfaceFont(.headline)
            row("材料密度","Density","g/cm³");row("额外耗料","ExtraWasteG","g")
            ContextHelp("丝材直径 1.75 mm。用量与时间包含 149 路径，不含官方启动排料、预热、调平和 AMS 换料。")
            Divider()
            Link(L("安装 Bambu Connect"),destination:URL(string:"https://wiki.bambulab.com/en/software/bambu-connect")!).foregroundColor(.primary)
            ContextHelp("首次使用请先在 Bambu Connect 登录并连接机器。发送后在官方窗口确认打印，不重新切片。")
        }
    }
}

struct FilamentFlowAssessment:View {
    @ObservedObject var model:Workbench
    @ObservedObject private var language=AppLanguage.shared
    struct Entry:Identifiable {
        let id:String;let width:Double;let height:Double;let speed:Double;let factor:Double
        var area:Double {height*(width-height*(1-Double.pi/4))*factor}
        var demand:Double {area*speed}
    }
    func n(_ key:String)->Double {Double(model.fields[key] ?? "") ?? .nan}
    var entries:[Entry] {
        let bottom=model.toggle("HasBottom").wrappedValue && !["Triple","DoubleScroll","SingleBud","CornerPipe","EggScroll","Wardrobe"].contains(model.fields["SourceMode"] ?? "")
        let w=bottom ? n("WB"):n("W")
        var rows=[Entry(id:"首层",width:w,height:n("H0"),speed:n(bottom ? "BottomF":"WallF"),factor:n("FM")*n("F0")),
                  Entry(id:"外墙",width:n("W"),height:n(model.fields["SourceMode"]=="Triple" ? "TriplePitch":"H"),speed:n("WallF"),factor:n("FM")),
                  Entry(id:"裙边",width:w,height:n("H0"),speed:n("SKIRT_F"),factor:n("FM")*n("F0"))]
        if !model.toggle("SKIRT_AUTO").wrappedValue {rows.removeLast()}
        if bottom && n("B")>1 {rows.append(Entry(id:"底部",width:n("WB"),height:n("BH"),speed:n("BottomF"),factor:n("FM")))}
        return rows
    }
    var valid:Bool {n("MaxVolumetric").isFinite && n("MaxVolumetric")>0 && entries.allSatisfy{$0.width.isFinite && $0.height.isFinite && $0.speed.isFinite && $0.factor.isFinite && $0.height>0 && $0.width >= $0.height && $0.speed>0 && $0.factor>0}}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            uiText("流量评估 · MVS").interfaceFont(.subheadline,weight:.semibold)
            if valid {
                HStack {uiText("路径");Spacer();uiText("需求 mm³/s");uiText("限流后 mm/s").frame(width:105,alignment:.trailing)}.interfaceFont(.caption).foregroundColor(.secondary)
                ForEach(entries) {entry in
                    HStack {
                        uiText(entry.id);Spacer()
                        Text(String(format:"%.2f",entry.demand)).monospacedDigit().foregroundColor(entry.demand>n("MaxVolumetric") ? .orange:.primary)
                        Text(String(format:"%.2f",min(entry.speed,n("MaxVolumetric")/entry.area))).monospacedDigit().frame(width:105,alignment:.trailing)
                    }.interfaceFont(.callout)
                }
                ContextHelp("需求按设定速度估算；超过 MVS 时自动降速，保留挤出体积。MVS 是你设定的材料与热端上限，不是软件测出的机器能力。")
                if let flow=model.preview?.flow_report,!model.dirty {
                    Divider()
                    uiText(String(format:"路径峰值：需求 %.2f → 输出 %.2f mm³/s",flow.requested_peak,flow.effective_peak)).interfaceFont(.caption).monospacedDigit()
                    uiText(String(format:"限流线段：%d",flow.limited_segments)).interfaceFont(.caption)
                }
                if n("Nozzle")>0 {
                    let height=entries.map(\.height).max() ?? 0
                    let width=entries.map(\.width).max() ?? 0
                    uiText(String(format:"层高 / 孔径 %.2f× · 线宽 / 孔径 %.2f×",height/n("Nozzle"),width/n("Nozzle"))).interfaceFont(.caption).monospacedDigit()
                    if height/n("Nozzle")>0.8 || width/n("Nozzle")>2 {
                        uiText("实验挤出：较高层高或较宽料道可能贴合不足、拖拽或尺寸不稳。降速只降低流量需求，不能保证成形；估算截面也不等于实测料道。").interfaceFont(.caption).foregroundColor(.orange)
                    }
                }
            } else {uiText("输入有效的线宽、层高、速度和流量比例后显示估算。").interfaceFont(.caption).foregroundColor(.secondary)}
        }.padding(10).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
    }
}
