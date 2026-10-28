import SwiftUI
import Foundation

struct WardrobeEFControls:View {
    @ObservedObject var model:Workbench
    private var grouped:Bool { model.toggle("WardEFGrouped").wrappedValue && Double(model.fields["WardLayout"] ?? "0")==2 }
    private var post:Bool {
        grouped && !model.toggle("WardBedTest").wrappedValue && [1.0,2.0,3.0,4.0].contains(Double(model.fields["WardPart"] ?? "0") ?? 0)
    }
    private var layerCount:Int { post ? 9:7 }
    private var layerKey:String { post ? "WardPostEFLayer":"WardEFLayer" }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            uiText("挂衣体 · 几何 EF").interfaceFont(.headline)
            Toggle(L("启用挂衣体 EF"),isOn:model.toggle("WardEFEnabled"))
            Toggle(L("使用实测逐层补偿"),isOn:model.toggle("WardEFMeasured"))
            if model.toggle("WardEFMeasured").wrappedValue {
                if Double(model.fields["WardLayout"] ?? "0")==2 {
                    Toggle(L("按梁与柱段分别补偿"),isOn:model.toggle("WardEFGrouped"))
                }
                uiText(grouped ? (post ? "当前补偿组：②③④⑤柱段":"当前补偿组：①底梁、⑥顶梁"):"当前补偿组：所有分件共用").interfaceFont(.subheadline)
                ForEach(1...layerCount,id: \.self) { layer in
                    NumberRow(model:model,label:"第 \(layer) 层内缩",key:"\(layerKey)\(layer)",unit:"mm")
                }
                ContextHelp("每个分件从自己的打印首层计数，上段倒置时也一样；第\(layerCount+1)层起补偿为0。数值为各层目标，连续升Z时层间平滑过渡；第2层可独立设为0。替换首层旧补偿，不叠加。")
                if grouped {
                    ContextHelp("两组数值分别保存，切换分件自动调用对应组；修改当前表只影响同组分件。整件底部少层测试使用底梁组。")
                }
            } else {
                NumberRow(model:model,label:"首层轮廓内缩量",key:"WardEF",unit:"mm")
                uiText("首层全量补偿，随后一个上升圈平滑恢复原轮廓。").interfaceFont(.caption).foregroundColor(.secondary)
            }
            ContextHelp("移动走线路径，保留线宽；两道墙之间的净隙会减小，最大内缩量须小于双墙净隙的一半。裙边不补偿。")

        }
    }
}

struct EFPreset:Codable,Identifiable {
    var id:String=UUID().uuidString
    var name:String
    var fields:[String:String]
}
final class EFPresetStore:ObservableObject {
    static let keys=["EF","EFLayers","EFTable","EFEnabled"]
    @Published private(set) var presets:[EFPreset]=[]
    private let defaults:UserDefaults
    private let key="efNamedPresetsV1"
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        reload()
    }
    func reload() {
        if let data=defaults.data(forKey:key),let saved=try? JSONDecoder().decode([EFPreset].self,from:data) {presets=saved}
    }
    func save(name:String,fields:[String:String],replacing:String?=nil)throws->String {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else {throw NSError(domain:"EF",code:1,userInfo:[NSLocalizedDescriptionKey:"请给预设填写一个名称。"])}
        guard !presets.contains(where:{$0.name==name && $0.id != replacing}) else {throw NSError(domain:"EF",code:2,userInfo:[NSLocalizedDescriptionKey:"已有同名预设，请换一个名称或点击更新。"])}
        var next=presets
        let item=EFPreset(id:replacing ?? UUID().uuidString,name:name,fields:Dictionary(uniqueKeysWithValues:Self.keys.map{($0,fields[$0] ?? "")}))
        if let i=next.firstIndex(where:{$0.id==item.id}) {next[i]=item} else {next.append(item)}
        let data=try JSONEncoder().encode(next);defaults.set(data,forKey:key);presets=next;return item.id
    }
    func remove(_ id:String)throws {let next=presets.filter{$0.id != id};defaults.set(try JSONEncoder().encode(next),forKey:key);presets=next}
}
struct EFPresetControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    @StateObject private var store=EFPresetStore()
    private var selected:String {
        get {model.selectedEFPresetID}
        nonmutating set {model.selectedEFPresetID=newValue}
    }
    @State private var name=""
    @State private var notice=""
    @State private var deleting=false
    @State private var naming=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            PresetHeader("补偿预设") {
                Button(L("存为新预设…")){name="";naming=true}
                Button(L("更新当前预设")){save(true)}.disabled(selected.isEmpty)
                Divider()
                Button(L("删除预设…"),role:.destructive){deleting=true}.disabled(selected.isEmpty)
            }
            Picker(L("预设"),selection:Binding(get:{selected},set:{id in
                selected=id
                guard let p=store.presets.first(where:{$0.id==id}) else{return}
                model.applyEFPreset(p);name=p.name;notice=""
            })) {
                uiText("选择已保存的预设").tag("")
                ForEach(store.presets) {Text(verbatim:$0.name).tag($0.id)}
            }.labelsHidden().id(appLanguage.code).accessibilityLabel(L("象脚补偿预设"))
            if let p=store.presets.first(where:{$0.id==selected}),p.fields.contains(where:{model.fields[$0.key] != $0.value}) {
                uiText("已修改").font(.caption).foregroundStyle(.secondary)
            }
            if !notice.isEmpty {uiText(notice).interfaceFont(.caption).foregroundColor(.secondary)}

        }
        .onChange(of:model.calibrationRevision){_ in store.reload()}
        .popover(isPresented:$naming) {
            VStack(alignment:.leading,spacing:12) {
                uiText("预设名称").font(.headline)
                TextField(L("例如：圆筒灯罩 · PETG · 12 圈"),text:$name).textFieldStyle(.roundedBorder).onSubmit{save(false)}
                HStack {Button(L("取消")){naming=false};Spacer();Button(L("保存")){save(false)}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            }.padding(16).frame(width:280)
        }
        .alert(L("删除这个补偿预设？"),isPresented:$deleting) {
            Button(L("取消"),role:.cancel){}
            Button(L("删除"),role:.destructive){do{try store.remove(selected);selected="";notice="预设已删除，当前补偿参数仍保留。"}catch{model.error=error.localizedDescription}}
        }
    }
    func save(_ replace:Bool) {
        do {
            let label=replace ? (store.presets.first{$0.id==selected}?.name ?? ""):name
            selected=try store.save(name:label,fields:model.fields,replacing:replace ? selected:nil)
            naming=false;notice="已保存：\(label)"
        } catch {model.error=error.localizedDescription}
    }
}

extension Workbench {
    func applyEFPreset(_ preset:EFPreset) {
        selectedEFPresetID=preset.id
        let next=fields.merging(preset.fields){_,new in new}
        guard next != fields else{return}
        fields=next;dirty=true
    }
}

struct CompensationControls:View {
    @ObservedObject var model:Workbench
    func row(_ label:String,_ key:String,_ unit:String="mm")->some View {NumberRow(model:model,label:label,key:key,unit:unit)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
                        if model.fields["SourceMode"] == "Wardrobe" {
                            WardrobeEFControls(model:model)
                        } else if model.fields["SourceMode"] == "DoubleScroll" && model.fields["DoubleLines"] == "1" {
                            uiText("单线开放走线暂不应用 EF").interfaceFont(.headline)
                            uiText("请在造型页选择双线闭合或花瓶走线，使用闭合轮廓内缩补偿。当前 EF 数值和逐圈表会保留。").interfaceFont(.callout).foregroundColor(.secondary)
                        } else if ["Triple","TripleVase","Crescent","SingleBud","CornerPipe","EggScroll","Wardrobe","TravelTest","Fern1060","Fern1060E","PipeScroll","PelletBottle"].contains(model.fields["SourceMode"] ?? "") {
                            uiText("此造型暂不应用 EF").interfaceFont(.headline)
                            uiText("保留当前卷曲路径尺寸。圆柱和锥形的 EF 数值仍保存在项目中，切回后可继续调整。").interfaceFont(.callout).foregroundColor(.secondary)
                        } else {
                        EFPresetControls(model:model)
                        Toggle(L("启用象脚补偿"),isOn:model.toggle("EFEnabled"))
                        if model.fields["SourceMode"] == "DoubleScroll" {
                            ContextHelp("沿闭合轮廓向内补偿，首层保持等高，之后按圈恢复原尺寸。内缩量须小于双线净间隙的一半；裙边与顶部整平规律保留。")
                        }
                        VStack(alignment:.leading,spacing:10) {
                        row("最大内缩量","EF");row("过渡范围","EFLayers","圈")
                        ContextHelp("底部按设定值内缩，随后逐渐减弱。关闭开关会保留参数与校准数据。")
                        DisclosureGroup(L("自定义补偿曲线")) {
                        uiText("保留校准生成的数据；只有需要单独修正时才编辑。").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text:model.binding("EFTable")).font(.system(.body,design:.monospaced)).frame(minHeight:270).padding(6).background(Color(nsColor:.textBackgroundColor)).cornerRadius(6)
                        ContextHelp("0 表示墙体起点；最后一圈应为 0%。例如 5:47 表示第 5 圈处使用 EF 的 47%。中间圈需齐全，比例需保持不变或递减。\n留空时按补偿圈数平滑递减。")
                        }
                                                }.disabled(!model.toggle("EFEnabled").wrappedValue)
                        }
                        EdgeCalibrationControls(model:model)
        }
    }
}
