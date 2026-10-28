import SwiftUI
import Foundation

struct NoisePreset:Codable,Identifiable {
    var id:String=UUID().uuidString
    var name:String
    var fields:[String:String]
}
final class NoisePresetStore:ObservableObject {
    static let keys=["NoiseEnabled","NoiseAmplitude","NoiseScale","NoiseVariation","NoiseSeed","NoiseZEnabled","NoiseZAmplitude","NoiseStrength"]
    @Published private(set) var presets:[NoisePreset]=[]
    private let defaults:UserDefaults
    private let key="noiseNamedPresetsV1"
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:key),let saved=try? JSONDecoder().decode([NoisePreset].self,from:data) {presets=saved}
    }
    func save(name:String,fields:[String:String],replacing:String?=nil)throws->String {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else {throw NSError(domain:"Noise",code:1,userInfo:[NSLocalizedDescriptionKey:L("请给预设填写一个名称。")])}
        guard !presets.contains(where:{$0.name==name && $0.id != replacing}) else {throw NSError(domain:"Noise",code:2,userInfo:[NSLocalizedDescriptionKey:L("已有同名预设，请换一个名称或点击更新。")])}
        var next=presets
        let item=NoisePreset(id:replacing ?? UUID().uuidString,name:name,fields:Dictionary(uniqueKeysWithValues:Self.keys.map{($0,fields[$0] ?? ($0=="NoiseStrength" ? "1":"0"))}))
        if let i=next.firstIndex(where:{$0.id==item.id}) {next[i]=item} else {next.append(item)}
        let data=try JSONEncoder().encode(next);defaults.set(data,forKey:key);presets=next;return item.id
    }
    func remove(_ id:String)throws {let next=presets.filter{$0.id != id};defaults.set(try JSONEncoder().encode(next),forKey:key);presets=next}
    static func applying(_ preset:NoisePreset,to fields:[String:String])->[String:String] {
        var result=fields
        for key in keys {if let value=preset.fields[key] {result[key]=value}}
        if ["1","true","1.0"].contains(result["NoiseEnabled"] ?? "") {result["WaveEnabled"]="0";result["MeshEnabled"]="0"}
        return result
    }
}
struct NoisePresetControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    @StateObject private var store=NoisePresetStore()
    private var selected:String {
        get {model.selectedNoisePresetID}
        nonmutating set {model.selectedNoisePresetID=newValue}
    }
    @State private var name=""
    @State private var notice=""
    @State private var deleting=false
    @State private var naming=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            PresetHeader("随机波预设") {
                Button(L("存为新预设…")){name="";naming=true}
                Button(L("更新当前预设")){save(true)}.disabled(selected.isEmpty)
                Divider()
                Button(L("删除预设…"),role:.destructive){deleting=true}.disabled(selected.isEmpty)
            }
            Picker(L("预设"),selection:Binding(get:{selected},set:{id in
                selected=id
                guard let p=store.presets.first(where:{$0.id==id}) else{return}
                model.applyNoisePreset(p);name=p.name;notice=""
            })) {
                uiText("选择已保存的预设").tag("")
                ForEach(store.presets) {Text(verbatim:$0.name).tag($0.id)}
            }.labelsHidden().id(appLanguage.code).accessibilityLabel(L("随机波预设")).disabled(!model.supportsNoise)
            if let p=store.presets.first(where:{$0.id==selected}),p.fields.contains(where:{model.fields[$0.key] != $0.value}) {
                uiText("已修改").font(.caption).foregroundStyle(.secondary)
            }
            if !notice.isEmpty {uiText(notice).interfaceFont(.caption).foregroundColor(.secondary)}

        }
        .popover(isPresented:$naming) {
            VStack(alignment:.leading,spacing:12) {
                uiText("预设名称").font(.headline)
                TextField(L("预设名称"),text:$name).textFieldStyle(.roundedBorder).onSubmit{save(false)}
                HStack {Button(L("取消")){naming=false};Spacer();Button(L("保存")){save(false)}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            }.padding(16).frame(width:280)
        }
        .alert(L("删除这个随机波预设？"),isPresented:$deleting) {
            Button(L("取消"),role:.cancel){}
            Button(L("删除"),role:.destructive){do{try store.remove(selected);selected="";notice="预设已删除，当前参数仍保留。"}catch{model.error=error.localizedDescription}}
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
    var supportsNoise:Bool {["Cylinder","Cone"].contains(fields["SourceMode"] ?? "")}
    var supportsMesh:Bool {["Cylinder","Ellipse"].contains(fields["SourceMode"] ?? "")}
    func applyNoisePreset(_ preset:NoisePreset) {
        guard supportsNoise else{return}
        selectedNoisePresetID=preset.id
        let next=NoisePresetStore.applying(preset,to:fields)
        guard next != fields else{return}
        fields=next;dirty=true
    }
}
