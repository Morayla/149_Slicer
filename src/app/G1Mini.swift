import SwiftUI
import AppKit
import Foundation
import CoreFoundation
import UniformTypeIdentifiers

struct PreviewResult: Codable {
    struct WaveFit:Codable {let requested:Double;let effective:Double;let kind:String}
    let wave_fit:WaveFit?
    struct MeshFit:Codable {let requested:Double;let effective:Double;let opening:Double;let pitch:Double;let turns:Int}
    let mesh_fit:MeshFit?
    struct NoiseFit:Codable {let requested:Double;let effective:Double;let scale:Double;let z_effective:Double?}
    let noise_fit:NoiseFit?
    struct LampReference:Codable {let center:[Double];let diameter:Double}
    let lamp_reference:LampReference?
    struct Layer:Codable {let start:Int;let end:Int;let z:Double}
    struct FlowReport:Codable {let requested_peak:Double;let effective_peak:Double;let limited_segments:Int;let limit:Double}
    let flow_report:FlowReport?
    var layers:[Layer]?=nil
    var layer_heights:[Double]?=nil
    var layerHeightColors:LayerHeightColors {LayerHeightColors(heights:layer_heights ?? [])}
    func displayLayerHeight(_ index:Int)->Double {
        guard let heights=layer_heights,index>=0,index<heights.count else{return 0}
        return heights[index]
    }
    struct Summary: Codable {
        struct Assembly:Codable {let mass_g:Double;let part_count:Int;let parts_g:[Double];let scope:String;let method:String;let estimated:Bool;let motion_minutes:Double?}
        let assembly:Assembly?
        let segments: Int
        let volume_mm3: Double
        let path_mm: Double
        let motion_minutes: Double
        let compute_seconds: Double
        let model_dimensions_mm: [Double]?
        let mass_g: Double
        let model_mass_g: Double
        let skirt_mass_g: Double
        let extra_mass_g: Double
        let density_g_cm3: Double
    }
    let bed_size: [Double]?
    let machine_name: String?
    var bedSize:[Double] {bed_size ?? [1000,1000,1000]}
    let ok: Bool
    let preview_schema: Int
    let ranges: [String:[Double]]
    var segments: [[Double]]
    var beads: [[Double]]
    let sha256: String
    let height: Double
    let summary: Summary
    let info: String
}

enum PreviewMode:String,CaseIterable,Identifiable {
    case xray="X 光", role="路径类型", flow="体积流量", height="层高", speed="速度"
    var id:String {rawValue}
    var index:Int {switch self {case .flow:return 7;case .height:return 8;case .speed:return 9;case .role,.xray:return 6}}
    var unit:String {switch self {case .flow:return "mm³/s";case .height:return "mm";case .speed:return "mm/s";case .role,.xray:return ""}}
    var detail:String {
        switch self {
        case .xray:return "中性白色透视轮廓与逐层料道。保留完整打印几何；分析模式仍用彩色显示数值。"
        case .role:return "颜色区分裙边、底部、墙体与收尾。"
        case .flow:return "指令体积流量 = E ÷ 该段运动时间，包含流量倍率；不是实测出料量。"
        case .height:return "按首层、底部和墙体的打印层高分色；螺旋起步与收尾的局部挤出间隙不单独分档。可变层高按整层或整圈的规划层高显示。"
        case .speed:return "显示 F 指定的路径速度，不含固件加减速；勾选空移可比较移动速度。"
        }
    }
    func label(_ value:Double)->String {
        if value != 0 && abs(value)<0.001 {return String(format:"%.1e",value)}
        return String(format:self == .height ? "%.3f":"%.2f",value)
    }
}

func metricColor(_ fraction:Double)->Color {
    let rgb=previewMetricRGB(fraction)
    return Color(red:rgb[0],green:rgb[1],blue:rgb[2])
}

extension PreviewResult {
    func limits(_ mode:PreviewMode,_ showTravel:Bool)->[Double] {
        let key = mode == .flow ? "flow" : mode == .height ? "layer_height" : showTravel ? "all_speed":"print_speed"
        return ranges[key] ?? [0,0]
    }
}

struct LayerHeightLegend:View {
    let scale:LayerHeightColors
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                uiText("层高 · mm").interfaceFont(.caption,weight:.bold)
                Spacer()
                uiText("按打印层高分色").interfaceFont(.caption).foregroundColor(.secondary)
            }
            ScrollView(.vertical) {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:115),alignment:.leading)],alignment:.leading,spacing:6) {
                    ForEach(scale.entries) {entry in
                        HStack(spacing:6) {
                            RoundedRectangle(cornerRadius:3)
                                .fill(Color(red:entry.rgb[0],green:entry.rgb[1],blue:entry.rgb[2]))
                                .frame(width:20,height:12)
                            Text(entry.label+" mm").interfaceFont(.caption).monospacedDigit()
                        }.accessibilityElement(children:.combine)
                    }
                }.padding(.trailing,10)
            }.frame(height:scale.entries.count>6 ? 64:24)
            if scale.entries.count>6 {
                uiText("可滚动查看全部打印层高。").interfaceFont(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct MetricLegend:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    let mode:PreviewMode
    let limits:[Double]
    private var uniform:Bool {abs(limits[1]-limits[0])<0.0000001}
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                uiText("\(L(mode.rawValue)) · \(mode.unit)").interfaceFont(.caption,weight:.bold)
                Spacer()
                uiText(uniform ? "数值一致":"色标固定为整件路径范围").interfaceFont(.caption).foregroundColor(.secondary)
            }
            if uniform {
                RoundedRectangle(cornerRadius:3).fill(metricColor(0.5)).frame(height:8)
                uiText(mode.label(limits[0])+" "+mode.unit).interfaceFont(.caption).monospacedDigit()
            } else {
                RoundedRectangle(cornerRadius:3).fill(LinearGradient(colors:(0...16).map{metricColor(Double($0)/16)},startPoint:.leading,endPoint:.trailing)).frame(height:8)
                HStack {
                    uiText(mode.label(limits[0]));Spacer();uiText(mode.label((limits[0]+limits[1])/2));Spacer();uiText(mode.label(limits[1]))
                }.interfaceFont(.caption).monospacedDigit()
            }
        }
    }
}

final class Workbench: ObservableObject {
    @Published var parameterTab=0
    @Published var compensationReviewPending=false
    @Published var selectedEFPresetID=""
    @Published var selectedNoisePresetID=""
    @Published var showSendSheet=false
    @Published var documentURL:URL?
    private var shapeDrafts:[String:[String:String]]=[:]
    private var draftTask:DispatchWorkItem?
    var canSlice:Bool {!calibrationActive && !busy && !modelRefreshing && !modelNeedsUpdate && modelError==nil}
    var canSend:Bool {!calibrationActive && !busy && !dirty && preview != nil}
    var canImport:Bool {!calibrationActive && !busy}
    var sendTitle:String {isBambu ? "发送到 Bambu Connect…":"发送…"}
    func requestSend() {guard canSend else{return};if isBambu {sendToBambu()}else{showSendSheet=true}}
    func persistDraft() {
        draftTask?.cancel()
        let draft=fields,store=preferences,printer=printerModel
        let task=DispatchWorkItem {store.set(draft,forKey:"149.machine.fields."+printer);store.set(printer,forKey:"149.lastPrinter")}
        draftTask=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:task)
    }
    func flushDraft() {
        draftTask?.cancel()
        preferences.set(fields,forKey:"149.machine.fields."+printerModel)
        preferences.set(printerModel,forKey:"149.lastPrinter")
    }
    func rememberShape() {
        let keys=Set((defaults["shape"] as? [String:Any] ?? [:]).keys).union((defaults["process"] as? [String:Any] ?? [:]).keys)
        shapeDrafts[printerModel+":"+(fields["SourceMode"] ?? "")]=fields.filter{keys.contains($0.key)}
    }
    @Published var calibrationRevision=0
    @Published var calibrationActive=false
    @Published var calibrationLoading=true
    @Published var calibrationLoadError:String?
    @Published var calibrationLoadID=UUID()
    @Published var calibrationSidebarCollapsed=false
    @Published var calibrationPresentation=false
    @Published var calibrationRequest:[String]=[]
    func requestCalibration(_ command:String){calibrationRequest=[UUID().uuidString,command]}
    func openWorkspaceDocument(){if calibrationActive{requestCalibration("open")}else{openProject()}}
    func saveWorkspaceDocument(){if calibrationActive{requestCalibration("save")}else{saveProject()}}
    func saveWorkspaceDocumentAs(){if calibrationActive{requestCalibration("saveAs")}else{saveProject(asNew:true)}}
    @Published var fields: [String:String] = [:]
    @Published var preview: PreviewResult?
    @Published var modelGeometry:ModelGeometry?
    @Published var showingModel=true
    @Published var previewMode:PreviewMode = .role
    @Published var showTravel=false
    @Published var showBed=false
    @Published var showBeads=true
    @Published var panMode=false
    @Published var beadViewAction=0
    @Published var previewZoom=1.0
    func cameraAction(_ mode:Int) {
        if [0,2,6].contains(mode) {previewZoom=1}
        if mode==0 {panMode=false}
        if mode==6 {showBed=true}
        beadViewAction=((beadViewAction/10)+1)*10+mode
    }
    @Published var operation=""
    private var preparedModel:NativePreparedModel?
    private var preparedFields:[String:String]=[:]
    var modelNeedsUpdate:Bool {preparedModel==nil || preparedFields != modelInputs}
    private var modelInputs:[String:String] {
        var keys=Set((defaults["shape"] as? [String:Any] ?? [:]).keys)
        keys.formUnion((defaults["process"] as? [String:Any] ?? [:]).keys)
        keys.insert("PrinterModel")
        if ["1","true","1.0"].contains(fields["EdgeCalibrationEnabled"] ?? "") {keys.formUnion(["PF","FM","F0"])}
        return fields.filter{keys.contains($0.key)}
    }
    @Published var modelRefreshing=false
    @Published var modelError:String?
    private var modelRevision=0
    private var modelTask:DispatchWorkItem?
    private var modelComputation:SliceComputation?
    private var modelRunning=false
    private let modelQueue=DispatchQueue(label:"149.model-preview",qos:.userInitiated)
    private var modelCache:[(inputs:[String:String],prepared:NativePreparedModel,geometry:ModelGeometry)]=[]
    func suspendModelPreview() {
        modelRevision+=1;modelTask?.cancel();modelComputation?.cancel();modelRefreshing=false
    }
    func scheduleModelPreview(immediate:Bool=false) {
        guard !busy,!calibrationActive else{return}
        modelRevision+=1;modelTask?.cancel();modelComputation?.cancel();modelError=nil
        guard modelNeedsUpdate else {modelRefreshing=false;return}
        showingModel=true;dirty=true;modelRefreshing=true
        let inputs=modelInputs
        if fields["SourceMode"] != "Imported",let cached=modelCache.first(where:{$0.inputs==inputs}) {
            preparedModel=cached.prepared;preparedFields=inputs;modelGeometry=cached.geometry;modelRefreshing=false;return
        }
        guard !modelRunning else{return}
        let work=DispatchWorkItem{[weak self] in self?.generateModel()};modelTask=work
        DispatchQueue.main.asyncAfter(deadline:.now()+(immediate ? 0:0.3),execute:work)
    }
    func generateModel() {
        guard !busy,!modelRunning,modelNeedsUpdate else {modelRefreshing=false;return}
        let revision=modelRevision,inputs=modelInputs
        do {
            guard let engine=engine else {throw message("原生切片引擎未能初始化。")}
            let raw=try project()
            let computation=SliceComputation();modelComputation=computation
            modelRunning=true;modelRefreshing=true;modelError=nil
            modelQueue.async { [weak self] in
                do {
                    let (prepared,geometry)=try computation.run {let prepared=try engine.prepareModel(raw);return (prepared,try ModelGeometry(prepared))}
                    DispatchQueue.main.async {
                        guard let self=self else{return};self.modelRunning=false
                        guard revision==self.modelRevision,inputs==self.modelInputs else {self.scheduleModelPreview(immediate:true);return}
                        self.preparedModel=prepared;self.preparedFields=inputs;self.modelGeometry=geometry
                        self.modelRefreshing=false;self.modelError=nil
                        if self.fields["SourceMode"] != "Imported",prepared.shape.wall.count<50000 {
                            self.modelCache.removeAll{$0.inputs==inputs};self.modelCache.append((inputs,prepared,geometry))
                            if self.modelCache.count>2 {self.modelCache.removeFirst()}
                        }
                    }
                } catch {DispatchQueue.main.async {
                    guard let self=self else{return};self.modelRunning=false
                    guard revision==self.modelRevision else {self.scheduleModelPreview(immediate:true);return}
                    self.modelRefreshing=false;self.modelError=error.localizedDescription
                }}
            }
        } catch {modelRefreshing=false;modelError=error.localizedDescription}
    }
    @Published var busy = false
    @Published var dirty = true
    @Published var status = "选择造型并设置尺寸。"
    @Published var error: String?
    @Published var savedURL: URL?
    @Published var zLimit = 150.0
    private let speedKeys:Set<String> = ["F","BottomF","WallF","SKIRT_F","G1_TRAVEL_F","G1_Z_F","G1_RETRACT_F","G1_RESTORE_F","G1_WIPE_F"]
    private var defaults: [String:Any] = [:]
    var gcodeURL: URL?
    private var tempFolder: URL?
    private var sliceCache: [Data:URL] = [:]
    private var sliceCacheOrder: [Data] = []
    private let resource:URL
    let preferences:UserDefaults
    private var engine:NativeSliceEngine?

    init(resource:URL = Bundle.main.resourceURL!, preferences:UserDefaults = .standard) {
        self.resource=resource;self.preferences=preferences
        do {
            let data = try Data(contentsOf: resource.appendingPathComponent("g1mini/defaults.json"))
            defaults = try JSONSerialization.jsonObject(with: data) as! [String:Any]
            engine = try NativeSliceEngine(resources:resource)
            try applyProject(defaults)
            if let name=preferences.string(forKey:"149.lastPrinter"),let draft=preferences.dictionary(forKey:"149.machine.fields."+name) as? [String:String] {
                fields.merge(draft,uniquingKeysWith:{$1})
            }
        } catch { self.error = "无法读取内置参数：\(error.localizedDescription)" }
    }
    deinit {
        for folder in Set(sliceCache.values) {try? FileManager.default.removeItem(at:folder)}
        if let folder=tempFolder {try? FileManager.default.removeItem(at:folder)}
    }
    func binding(_ key:String) -> Binding<String> {
        Binding(get: { self.fields[key] ?? "" }, set: { value in
            if key=="SourceMode" {
                guard value != self.fields[key] else{return}
                self.rememberShape()
                if let draft=self.shapeDrafts[self.printerModel+":"+value] {
                    self.fields.merge(draft,uniquingKeysWith:{$1});self.fields[key]=value;self.dirty=true;return
                }
            }
            let wasFern=["Fern1060","Fern1060E"].contains(self.fields["SourceMode"] ?? "")
            self.fields[key]=value
            if key=="SourceMode" && value=="Hopper" {
                self.fields.merge(["W":"8","WB":"8","H":"3.5","H0":"3.5","BH":"3.5","HasBottom":"0","N":"288","AlignLeft":"1","EdgeCalibrationEnabled":"0","WaveEnabled":"0","MeshEnabled":"0","NoiseEnabled":"0","NoiseZEnabled":"0"],uniquingKeysWith:{$1})
            }
            if key=="SourceMode" && value=="PelletBottle" {
                self.fields.merge(["W":"8","WB":"8","H":"3.5","H0":"3.5","BH":"3.5","B":"2","HasBottom":"1","BottomKind":"Solid","BottomPattern":"Zigzag","EFEnabled":"0","AlignLeft":"1","EdgeCalibrationEnabled":"0","WaveEnabled":"0","MeshEnabled":"0","NoiseEnabled":"0","NoiseZEnabled":"0"],uniquingKeysWith:{$1})
            }
            if key=="SourceMode" && value=="PipeScroll" {
                self.fields.merge(["PipeScrollProfile":"2","PipeScrollSpacing":"167.96","PipeScrollRot":"0","PipeScrollHeight":"250","W":"8","H":"3","H0":"2.5","HasBottom":"0","EFEnabled":"0","WaveEnabled":"0","MeshEnabled":"0","NoiseEnabled":"0","NoiseZEnabled":"0"],uniquingKeysWith:{$1})
            }
            if key=="PipeScrollProfile" {
                let profileDefaults:[String:String] = value=="2" ? ["W":"8","PipeScrollSpacing":"167.96","PipeScrollRot":"0","PipeScrollHeight":"250"] : (value=="1" ? ["W":"6","PipeScrollSpacing":"215","PipeScrollRot":"-6.4"] : ["W":"6","PipeScrollSpacing":"150","PipeScrollRot":"0"])
                self.fields.merge(profileDefaults,uniquingKeysWith:{$1})
            }
            if key=="SourceMode" && ["Fern1060","Fern1060E"].contains(value) && !wasFern {
                self.fields.merge(["W":"8","H":"3.5","H0":"3.5","HasBottom":"0","EFEnabled":"0","WaveEnabled":"0","MeshEnabled":"0","NoiseEnabled":"0","NoiseZEnabled":"0"],uniquingKeysWith:{$1})
            }
            self.dirty=true
        })
    }
    func toggle(_ key:String) -> Binding<Bool> {
        Binding(get: { ["1","true","1.0"].contains(self.fields[key] ?? "") }, set: { self.fields[key]=$0 ? "1" : "0"; self.dirty=true })
    }
    func project() throws -> [String:Any] {
        var output:[String:Any] = ["version":1]
        for group in ["shape","machine","process","material"] {
            let schema = defaults[group] as! [String:Any]
            var values:[String:Any] = [:]
            for (key,value) in schema {
                let raw=fields[key] ?? ""
                if value is String { values[key]=raw }
                else if let n=value as? NSNumber, CFGetTypeID(n)==CFBooleanGetTypeID() {
                    values[key]=["1","true","1.0"].contains(raw)
                } else {
                    guard let number=Double(raw), number.isFinite else { throw message("\(key) 请输入有效数字。") }
                    values[key]=speedKeys.contains(key) ? number*60 : number
                }
            }
            output[group]=values
        }
        return output
    }
    func message(_ s:String)->NSError { NSError(domain:"G1Mini",code:1,userInfo:[NSLocalizedDescriptionKey:s]) }
    func applyProject(_ raw:[String:Any]) throws {
        guard raw["version"] as? Int == 1 else { throw message("不支持的项目版本。") }
        var next:[String:String]=[:]
        for group in ["shape","machine","process","material"] {
            let values:[String:Any]
            if ["process","material"].contains(group) && raw[group] == nil { values=[:] }
            else if let existing=raw[group] as? [String:Any] { values=existing }
            else { throw message("项目缺少 \(group) 参数。") }
            let schema=defaults[group] as! [String:Any]
            if let unknown=values.keys.first(where:{schema[$0]==nil}) { throw message("本版不支持参数 \(unknown)。") }
            for (key,fallback) in schema {
                let value=values[key] ?? fallback
                if let s=value as? String { next[key]=s }
                else if let number=value as? NSNumber {
                    if speedKeys.contains(key) { next[key]=String(format:"%.9g",number.doubleValue/60) }
                    else if key.hasPrefix("WardEFLayer") || key.hasPrefix("WardPostEFLayer") { next[key]=String(format:"%.12g",number.doubleValue) }
                    else { next[key]=number.stringValue }
                }
                else { throw message("\(key) 参数格式无效。") }
            }
        }
        guard ["Cylinder","Ellipse","Cone","Triple","TripleVase","DoubleScroll","NonplanarCylinder","Imported","Crescent","SingleBud","CornerPipe","EggScroll","Wardrobe","TravelTest","Fern1060","Fern1060E","PipeScroll","PelletBottle","Hopper"].contains(next["SourceMode"] ?? "") else { throw message("不支持的造型类型。") }
        fields=next;dirty=true;savedURL=nil;documentURL=nil;shapeDrafts.removeAll();selectedEFPresetID="";selectedNoisePresetID=""
    }
    func writeProject(to url:URL) throws {
        let data=try JSONSerialization.data(withJSONObject:project(),options:[.prettyPrinted,.sortedKeys])
        try data.write(to:url,options:.atomic);documentURL=url;status="项目已保存：\(url.lastPathComponent)"
    }
    func saveProject(asNew:Bool=false) {
        do {
            if !asNew,let url=documentURL {try writeProject(to:url);return}
            let panel=NSSavePanel();panel.title=L(asNew ? "另存项目…":"保存项目")
            panel.nameFieldStringValue=documentURL?.lastPathComponent ?? L("149 项目.g1mini.json")
            guard panel.runModal() == .OK,let url=panel.url else{return}
            try writeProject(to:url)
        } catch {self.error=error.localizedDescription}
    }
    func openProject() {
        let panel=NSOpenPanel();panel.title=L("打开 149 项目");panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        guard panel.runModal()==NSApplication.ModalResponse.OK,let url=panel.url else{return}
        do {
            let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]
            guard let raw=raw else {throw message("项目格式无效。")}
            try applyProject(raw);documentURL=url;preview=nil;gcodeURL=nil;preparedModel=nil;modelGeometry=nil;showingModel=true
            status="已载入 \(url.lastPathComponent)，模型预览会自动更新。"
        } catch {self.error=error.localizedDescription}
    }
    func generate() {
        guard !busy,!calibrationActive else{return}
        guard !modelNeedsUpdate else {error="模型预览正在更新，请稍候。";return}
        do {
            guard let engine=engine else {throw message("原生切片引擎未能初始化。")}
            let data=try JSONSerialization.data(withJSONObject:project(),options:[.sortedKeys])
            // Imported files can change at the same path, including while the app
            // is open. Always let the engine read and validate their current bytes.
            let cacheable=fields["SourceMode"] != "Imported"
            let cachedFolder=cacheable ? sliceCache[data]:nil
            let folder=cachedFolder ?? FileManager.default.temporaryDirectory.appendingPathComponent("G1Mini-"+UUID().uuidString)
            let started=Date()
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if cachedFolder == nil {try data.write(to:folder.appendingPathComponent("project.json"))}
            preferences.set(fields,forKey:"149.machine.fields."+printerModel)
            preferences.set(printerModel,forKey:"149.lastPrinter")
            let prepared=preparedModel
            busy=true;operation="正在切片…";error=nil;savedURL=nil;status=cachedFolder == nil ? "正在生成路径与机器指令…":"正在载入此分件的已验证切片…"
            DispatchQueue.global(qos:.userInitiated).async {
                do {
                    let result:PreviewResult
                    var refreshedModel:NativePreparedModel?,refreshedGeometry:ModelGeometry?
                    if cachedFolder == nil {
                        let raw=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                        let generated=try engine.generate(raw,prepared:prepared)
                        try generated.write(to:folder)
                        result=try PreviewResult(native:generated)
                        if !cacheable,let prepared=prepared {
                            let fresh=NativePreparedModel(key:prepared.key,shape:generated.model)
                            refreshedGeometry=try ModelGeometry(fresh);refreshedModel=fresh
                        }
                        if cacheable {try JSONEncoder().encode(result).write(to:folder.appendingPathComponent("result.json"),options:.atomic)}
                    } else {
                        result=try JSONDecoder().decode(PreviewResult.self,from:Data(contentsOf:folder.appendingPathComponent("result.json")))
                    }
                    guard result.ok else {throw self.message("生成失败。")}
                    let elapsed=Date().timeIntervalSince(started),currentModel=refreshedModel,currentGeometry=refreshedGeometry
                    DispatchQueue.main.async {
                        if let currentModel=currentModel,let currentGeometry=currentGeometry {self.preparedModel=currentModel;self.modelGeometry=currentGeometry}
                        if let previous=self.tempFolder,previous != folder,!self.sliceCache.values.contains(previous) {
                            try? FileManager.default.removeItem(at:previous)
                        }
                        if cacheable {
                            self.sliceCache[data]=folder
                            self.sliceCacheOrder.removeAll {$0 == data};self.sliceCacheOrder.append(data)
                            while self.sliceCacheOrder.count>6 {
                                let key=self.sliceCacheOrder.removeFirst()
                                if let old=self.sliceCache.removeValue(forKey:key) {try? FileManager.default.removeItem(at:old)}
                            }
                        }
                        self.tempFolder=folder;self.gcodeURL=folder.appendingPathComponent("preview.gcode")
                        self.preview=result;self.zLimit=result.height;self.busy=false;self.operation="";self.dirty=false;self.showingModel=false
                        if let fit=result.wave_fit {self.fields["WaveCount"]=String(format:"%.9g",fit.effective)}
                        if let fit=result.mesh_fit {self.fields["MeshCount"]=String(format:"%.9g",fit.effective)}
                        self.preparedFields=self.modelInputs
                        self.status=String(format:cachedFolder == nil ? "切片及数据载入 · %.1f 秒":"复用分件切片 · %.1f 秒",elapsed)
                    }
                } catch {
                    try? FileManager.default.removeItem(at:folder)
                    DispatchQueue.main.async {self.sliceCache.removeValue(forKey:data);self.sliceCacheOrder.removeAll {$0 == data};self.busy=false;self.operation="";self.dirty=true;self.error=error.localizedDescription;self.status="生成未完成，请检查参数。"}
                }
            }
        } catch {self.error=error.localizedDescription}
    }
    func exportGcode() {
        guard !dirty,!busy,let source=gcodeURL else{return}
        let panel=NSSavePanel();panel.title=L("导出 G-code");panel.nameFieldStringValue=printerModel.replacingOccurrences(of:" ",with:"_")+"_Shape.gcode"
        guard panel.runModal()==NSApplication.ModalResponse.OK,let url=panel.url else{return}
        do {
            try Data(contentsOf:source).write(to:url,options:.atomic)
            savedURL=url;status="已导出：\(url.lastPathComponent)"
        } catch {self.error=error.localizedDescription}
    }
}

struct NumberRow: View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    let label:String
    let key:String
    var unit:String="mm"
    var body:some View {
        HStack {
            uiText(label).frame(maxWidth:.infinity,alignment:.leading)
            TextField(L(""),text:model.binding(key)).multilineTextAlignment(.trailing).monospacedDigit().frame(width:82).textFieldStyle(.roundedBorder)
            uiText(unit).interfaceFont(.caption).foregroundColor(.secondary).frame(width:38,alignment:.leading)
        }.frame(minHeight:30)
    }
}

struct ShapeControls: View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    @State private var wardrobeAdvanced=false
    private var triple:Bool {model.fields["SourceMode"] == "Triple"}
    private var travelTest:Bool {model.fields["SourceMode"] == "TravelTest"}
    private var wardrobe:Bool {model.fields["SourceMode"] == "Wardrobe"}
    private var egg:Bool {model.fields["SourceMode"] == "EggScroll"}
    private var fern:Bool {["Fern1060","Fern1060E"].contains(model.fields["SourceMode"] ?? "")}
    private var corner:Bool {model.fields["SourceMode"] == "CornerPipe"}
    private var bud:Bool {model.fields["SourceMode"] == "SingleBud"}
    private var pipeScroll:Bool {model.fields["SourceMode"] == "PipeScroll"}
    private var doubleScroll:Bool {model.fields["SourceMode"] == "DoubleScroll"}
    private var doubleVase:Bool {doubleScroll && model.fields["DoubleLines"] == "3"}
    private var vase:Bool {model.fields["SourceMode"] == "TripleVase"}
    private var bottle:Bool {model.fields["SourceMode"] == "PelletBottle"}
    private var cone:Bool {model.fields["SourceMode"] == "Cone"}
    private var nonplanar:Bool {model.fields["SourceMode"] == "NonplanarCylinder"}
    func row(_ label:String,_ key:String,_ unit:String="mm")->some View {NumberRow(model:model,label:label,key:key,unit:unit)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            
            Picker(L("造型"),selection:model.binding("SourceMode")) {
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
            }.accessibilityLabel(L("造型选择")).id(appLanguage.code)
            if model.fields["SourceMode"]=="Imported" {
                Button(L("选择 STL / OBJ / STEP…"),action:model.importModel).frame(maxWidth:.infinity,alignment:.leading)
                Text(verbatim:URL(fileURLWithPath:model.fields["ImportFile"] ?? "").lastPathComponent).interfaceFont(.caption).lineLimit(2).truncationMode(.middle)
                row("缩放比例","ImportScale","×")
                ContextHelp(
                    "Z 轴向上，自动落到平台；STL / OBJ 单位按毫米读取。导入外轮廓生成单壁，不沿用原模型壁厚。",
                    "STEP 使用内置原生 CAD 引擎读取。支持每层一个外轮廓的灯罩；分离轮廓、破洞或不支持的悬垂会提示错误。"
                )
            } else if model.fields["SourceMode"]=="Hopper" {
                HopperControls(model:model)
            } else if bottle {
                row("瓶身外径","BottleDiameter")
                row("直身高度","BottleBody")
                row("收口高度","BottleShoulder")
                row("直口高度","BottleNeck")
                row("瓶口内径","BottleBore")
                let h=["BottleBody","BottleShoulder","BottleNeck"].reduce(0.0){$0+(Double(model.fields[$1] ?? "0") ?? 0)}
                Text(String(format:"总高 %.1f mm · 默认约10 L内部容积，不代表10 kg颗粒。",h)).interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("打印时大底贴平台、瓶口朝上；使用时倒置。实心封底后单墙连续升Z，不加内填充或顶盖。瓶口外径随线宽变化，内径保持设定值。")
                uiText("圆柱—收口两端作短圆滑过渡；切片检查逐圈搭接，实际成形和气密需试印。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if fern {
                row("打印高度 / 进深","FernDepth")
                ContextHelp(
                    "正面高1060 × 宽469.9 mm保持不变；躺放45°。进深可在200–500.5 mm内调整，缩短后会重新检查逐圈搭接。",
                    "原版 / E版共享当前进深、层高与线宽；切换后点切片，比较下方材料用量。E版只截短卷尖，预计少约1.28%用料，并非整圈减半。独立上限50万段。"
                )
                uiText("外围裙边关闭，内部清料圈尚未加入；此项只生成本体路径。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if travelTest {
                row("跨孔距离","TravelTestSpan")
                row("往返轮数","TravelTestRounds","轮")
                let rounds=Double(model.fields["TravelTestRounds"] ?? "12") ?? 12
                let retract=model.fields["G1_RETRACT"] ?? "30"
                let extra=model.fields["G1_RESTART_EXTRA"] ?? "10"
                Text(String(format:L("预计打印高 %.1f mm；含首层和收口约 %.0f 次跨孔移动。"),2.5+rounds*3.5,2*rounds+3)).interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp(
                    "两座矮卷芯交替螺旋上升，起停点放在面向开孔的外露端。默认300 mm跨度、12轮；先用小样观察拉丝、重启缺料与积料。",
                    "固定：线宽8 mm · 双墙净隙1.2 mm · 层高3.5 mm · 首层2.5 mm · 打印9 mm/s · 空移抬升6 mm。",
                    "外围先打印一圈裙边，主体与裙边均为9 mm/s。沿用当前G1温度、回抽及重启补料；测试件固定居中。效果、EF与起始减流不参与。",
                    String(format:L("当前回抽 %@ mm³；重启额外补料 %@ mm³（可在「打印」中调整）。"),retract,extra),
                    "小样不代表最终大跨度或高件已通过。抬升仅提供路径避让；首次试印需观察积料、卷边与喷头净空。"
                )
            } else if wardrobe {
                WardrobeBedTestControls(model:model)
                Picker(L("打印分件"),selection:model.binding("WardPart")) {
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
                    } else { uiText("⑥顶梁 · 整件").tag("5") }
                }.pickerStyle(.menu).disabled(model.toggle("WardBedTest").wrappedValue)
                row("整体高度","WardHeight")
                row("开孔展开宽度","WardOpening")
                row("双墙净间隙","WardLaneGap")
                if (Double(model.fields["WardTipClearance"] ?? "0") ?? 0)>0 { uiText("卷尖至外圈净空已独立锁定，调整墙缝时保持。").interfaceFont(.caption).foregroundColor(.secondary) }
                if model.fields["WardCoreMode"] == "3" {
                    uiText("数学螺旋 · 粗线宽自动保留卷尖净空 · 管轴位置保留").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if model.fields["WardLayout"] == "2" && !model.toggle("WardBedTest").wrappedValue {
                    uiText("每次切片同时更新单件与整套六件的预计用料、打印时间；六件各打印一次，不含⑦和后装定位套。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                DisclosureGroup(L("结构与旧版参数"),isExpanded:$wardrobeAdvanced) {
                    Picker(L("挂衣方案"),selection:Binding(get:{model.fields["WardLayout"] ?? "0"},set:{model.fields["WardLayout"]=$0;model.fields["WardPart"]="0";model.dirty=true})) {
                        uiText("原六件 · 直接挂顶梁").tag("0")
                        uiText("九件 · 独立矮梁").tag("1")
                        uiText("六件框架 · 挂衣梁后装").tag("2")
                    }
                    row("上下梁等高","WardBeam")
                    if model.fields["WardLayout"] == "2" {
                        row("下段打印高度","WardLowerHeight")
                        row("顶部开孔圆角","WardTopRadius")
                    }
                    row("底部开孔圆角","WardRadius")
                    if model.fields["WardLayout"] == "1" {
                        row("挂衣矮梁高度","WardRailHeight")
                        row("衣摆距底梁","WardHemGap")
                    }
                    Picker(L("卷芯方式"),selection:model.binding("WardCoreMode")) {
                        uiText("数学螺旋 · 定位套后装").tag("3")
                        uiText("小卷芯 · 270°包裹").tag("2")
                        uiText("自然螺旋").tag("1")
                        uiText("原包管卷芯").tag("0")
                    }
                    if ["2","3"].contains(model.fields["WardCoreMode"] ?? "0") {row("卷芯最小净空","WardCoreBore")}
                    if model.fields["WardCoreMode"] != "3" {row("螺旋减卷角度","WardCurlReduction","°")}
                    row("连接柱外径","WardPipeD")
                    row("直径装配余量","WardClearance")
                    row("挂衣数量","WardCount","件")
                    row("每件挂放间距","WardPitch")
                    row("两端挂放余量","WardEndSpace")
                    Picker(L("层高策略"),selection:model.binding("WardLayerMode")) {
                        uiText("圆角细层").tag("0")
                        uiText("统一约设定层高").tag("1")
                    }
                }
                ContextHelp("每件双墙连续升 Z，无跨孔空移；上段倒置打印。首层与收口除外，主体按所设层高连续升 Z（支持至3.5 mm）。安装与承载仍需实物验证。")
            } else if egg {
                row("整体高度（使用时）","EggHeight")
                let h=Double(model.fields["EggHeight"] ?? "650") ?? 650
                Text(String(format:"进深自动 %.1f mm；宽度与双卷同步缩放。",h*80/650)).interfaceFont(.caption).foregroundColor(.secondary)
                uiText("只需改整体高度。蛋形比例、顶部短平面和海螺卷保持一致；打印线宽不随造型缩放。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("正面朝上平放打印，Z 轴生成进深；打印完成后立起使用。切片会检查卷尖回转与相邻料道净空，过小时提示最小高度。")
            } else if corner {
                row("墙角占位边长","CornerSide")
                row("模块高度","CornerHeight")
                row("连接管外径","CornerPipeD")
                row("直径装配余量","CornerClearance")
                row("双线净间隙","CornerLaneGap")
                uiText("两只同形双卷，右下角留贯穿管孔；底侧、右侧与 90° 墙面相切。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("管孔直径 = 管外径 + 装配余量。Ø21.3 管配 1 mm 余量，即 Ø22.3 孔、单边 0.5 mm。钢管本身不打印。")
                uiText("截面沿全高一致；闭合双线连续升 Z。改变尺寸后会重新检查通孔与料道间距。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if bud {
                row("参考外径（含料道）","BudD")
                row("模块高度","BudHeight")
                row("基准螺旋圈数","BudTurns","圈")
                row("涡心净空直径","BudCoreD")
                row("双线净间隙","BudLaneGap")
                row("卷边收拢角","BudCurl","°")
                row("收拢开始高度","BudStart")
                row("收拢结束高度","BudEnd")
                row("整体朝向","BudRot","°")
                ContextHelp(
                    "涡心固定，外侧卷边沿高度平滑收拢，形成侧面的 S 形花蕾边；收拢角为 0 时成为直壁螺旋柱。",
                    "一个螺旋，双壁闭合走线。卷入、内端折返、卷出、外端闭合时均连续升 Z；两道壁分别占用一个线宽。",
                    "外径为包含料道的参考圆上限；检查路径相交和层间搭接。过矮或收拢过急时，请减小层高或加长收拢区间。"
                )
            } else if pipeScroll {
                Picker(L("轮廓样式"),selection:model.binding("PipeScrollProfile")) {
                    uiText("原插管型").tag("0")
                    uiText("同心顺滑 · 原尺寸").tag("1")
                    uiText("8毫米线宽 · 卷尖加回15°").tag("2")
                }.pickerStyle(.menu)
                row("总高度","PipeScrollHeight")
                if model.fields["PipeScrollProfile"] != "2" {row("两卷芯中心距","PipeScrollSpacing")}
                row("平面旋转","PipeScrollRot","°")
                if model.fields["PipeScrollProfile"] == "2" {
                    ContextHelp("当前确认版：外形约285.2 × 118.3 mm；8 mm线宽，双墙净隙约1.5 mm。卷尖比红线截短版加回15°，两侧对称。完整蓝套内孔21.7、外径25.7 mm，配21.3 mm管；蓝套另行打印，当前用料不包含插套。")
                } else if model.fields["PipeScrollProfile"] == "1" {
                    ContextHelp("同心顺滑确认版：Ø21.3 mm管位于卷芯中心，通过独立定位套装配。卷芯净空29.7 mm，线宽6 mm，双墙净隙3 mm。中心距215 mm，水平旋转−6.4°；未缩小。")
                } else {
                    ContextHelp("内侧270°保留衣架卷芯，外圈缩小。沿用Ø21.3 mm管与原定位件；卷芯设定内径29.7 mm，双墙净隙3 mm。中心距可调120–230 mm；默认150 mm，原版为230 mm。")
                }
                ContextHelp("首层等高闭合，墙体连续升Z，顶部整平。管与固定套另行装配，不作为主体打印；调整高度不改变插管接口。")
            } else if doubleScroll {
                Picker(L("轮廓样式"),selection:model.binding("DoubleProfile")) {
                    uiText("镜像双卷").tag("0")
                    uiText("S 形双卷长灯").tag("1")
                    uiText("圆弧深卷（对称）").tag("2")
                    uiText("等距双螺旋（平顺）").tag("3")
                }.pickerStyle(.menu)
                Picker(L("走线方式"),selection:model.binding("DoubleLines")) {
                    uiText("单线开放").tag("1")
                    uiText("双线闭合").tag("2")
                    uiText("花瓶模式（连续升 Z）").tag("3")
                }.pickerStyle(.menu)
                if ["2","3"].contains(model.fields["DoubleLines"] ?? "1") {
                    row("双线净间隙","DoubleLaneGap")
                    uiText("一侧绕入，中心圆弧回转，沿另一侧绕出；两瓣连成闭合轮廓。净间隙不包含两侧料道的宽度。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if doubleVase {
                    ContextHelp("首层等高走完整个闭合轮廓，随后同向连续升 Z。层高为每周最大上升量，自动均分到完整周；顶部按剩余间隙整平。")
                    uiText("花瓶模式使用等距双螺旋；需要为两侧料道及内卷回转留出空间。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                row(["2","3"].contains(model.fields["DoubleProfile"] ?? "0") ? "参考圆外径":"单瓣外径","DoubleD")
                row("每侧螺旋圈数","DoubleTurns","圈")
                row(["2","3"].contains(model.fields["DoubleProfile"] ?? "0") ? "两圆参考外缘间距":"两螺旋外缘间距","DoubleGap")
                row(model.fields["DoubleProfile"] != "0" ? "灯体长度（打印高度）":"总高度","DoubleHeight")
                row("平面旋转","DoubleRot","°")
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
                row("路径外接直径","VaseD")
                row("总高度","VaseHeight")
                row("每瓣螺旋圈数","VaseTurns","圈")
                row("最小空腔直径","VaseCoreDiameter")
                row("平面旋转","TripleRot","°")
                uiText("每瓣圈数支持 1–6 圈，可输入 2.5 等小数。减少圈数可留出更多空间；上下截面一致。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("空腔直径为扣除线宽后的最小净空；减少圈数后自然变大的空腔会保留。外接直径按路径中心线计算，不含材料宽度。")
                uiText("完整三瓣实心底在「底部」调整；切片时检查相邻料道间距。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if triple {
                row("路径外接直径","TripleD")
                row("长螺旋圈数","TripleTurns","圈")
                row("总高度","TripleHeight")
                row("平面旋转","TripleRot","°")
                uiText("原脚本的三个阿基米德螺旋，连接成一条闭合路径。直径指路径中心线外接圆，不包含材料宽度。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if model.fields["SourceMode"] == "Crescent" {
                row("外径","CrescentD")
                row("总高度","CrescentHeight")
                row("月牙最厚处","CrescentThickness")
                row("开口净宽","CrescentGap")
                row("开口方向","CrescentRotation","°")
                row("灯泡参考直径","CrescentBulbD")
                uiText("一个深弯月围成灯罩，两端圆滑。灯泡虚线固定在外圆正中心，仅供定位，不参与打印。").interfaceFont(.caption).foregroundColor(.secondary)
                uiText("沿月牙边界打印空心壳体；不整块填实，不生成底盘或灯座。开口方向 0° 朝右。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if model.fields["SourceMode"] == "Ellipse" {
                row("长轴外径","EllipseMajor")
                row("短轴外径","EllipseMinor")
                row("总高度","EllipseHeight")
                row("平面旋转","EllipseRotation","°")
                uiText("两轴为完整外径，不是半径。上下截面一致；长短轴相等时为圆柱。").interfaceFont(.caption).foregroundColor(.secondary)
            } else if cone {
                row("下口外径","ConeBottomD")
                row("上口外径","ConeTopD")
                row("总高度","ConeHeight")
                ContextHelp("开口锥形 / 圆台灯罩，上下口径均需大于线宽；不收尖封顶。")
            } else {
                row("外径","Dout");row("总高度","CH")
                if nonplanar {
                    row("口沿下凹深度","NPDepth")
                    row("起伏开始高度","NPStart")
                    row("下凹方向","NPDirection","°")
                    uiText("两高两低，保持中间开口。总高度为口沿最高点；下凹深度为最高点与最低点的高度差。").interfaceFont(.caption).foregroundColor(.secondary)
                    uiText("已配套非平面走线：从起伏开始高度逐渐变形。方向 0° 为左右下凹，90° 为前后下凹。").interfaceFont(.caption).foregroundColor(.secondary)
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
                DisclosureGroup(L("采样精度")) {row("每转采样数","TriplePts","点")}
            } else {
                Divider()
                if model.toggle("AlignLeft").wrappedValue {
                    Label(L(model.isBambu ? "接缝固定在左侧 · 打印中可关闭":"接缝固定在左侧 · 打印中可关闭"),systemImage:"arrow.left.to.line").interfaceFont(.caption).foregroundColor(.secondary)
                } else {row("接缝角度","SeamAngle","°")}
            }
            }
        }
    }
}

struct WaveControls: View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    func row(_ label:String,_ key:String,_ unit:String="mm")->some View {NumberRow(model:model,label:label,key:key,unit:unit)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            NoisePresetControls(model:model)
            uiText("柔和随机波").interfaceFont(.headline)
            Toggle(L("启用柔和随机波"),isOn:Binding(get:{model.toggle("NoiseEnabled").wrappedValue},set:{value in
                model.toggle("NoiseEnabled").wrappedValue=value
                if value {model.toggle("WaveEnabled").wrappedValue=false;model.toggle("MeshEnabled").wrappedValue=false}
            })).disabled(!model.supportsNoise && !model.toggle("NoiseEnabled").wrappedValue)
            if !model.supportsNoise {uiText("柔和随机波目前支持圆柱与圆台造型。").font(.caption).foregroundStyle(.secondary)}
            if model.toggle("NoiseEnabled").wrappedValue {
                row("纹理强度","NoiseStrength","×")
                row("起伏幅度","NoiseAmplitude")
                row("波纹尺度","NoiseScale")
                row("层间变化","NoiseVariation","%")
                row("随机种子","NoiseSeed","")
                Toggle(L("垂直微起伏"),isOn:model.toggle("NoiseZEnabled"))
                if model.toggle("NoiseZEnabled").wrappedValue {row("垂直起伏幅度","NoiseZAmplitude")}
                uiText("适用于圆柱与圆台。轮廓向内、向外起伏；可叠加 Z 起伏，底部保持平整。").interfaceFont(.caption).foregroundColor(.secondary)
                uiText("尺度越大波纹越宽缓；层间变化越大，上下圈差异越明显。种子相同，纹理相同。").interfaceFont(.caption).foregroundColor(.secondary)
                uiText("幅度和尺度会按线宽、EF 与采样自动限制，以保留层间搭接。").interfaceFont(.caption).foregroundColor(.secondary)
                ContextHelp("垂直幅度自动限制在实际圈间高度的 10% 内；按局部间距和三维线长调整出料，首尾平缓过渡。")
                if let fit=model.preview?.noise_fit, !model.dirty {
                    uiText(String(format:"实际幅度上限 %.3f mm · 波纹尺度约 %.2f mm",fit.effective,fit.scale)).interfaceFont(.caption)
                    if let z=fit.z_effective,z>0 {uiText(String(format:"实际垂直幅度上限 %.3f mm",z)).interfaceFont(.caption)}
                }
            }
            Divider().padding(.vertical,4)
            uiText("波浪网孔（实验）").interfaceFont(.headline)
            Toggle(L("启用波浪网孔"),isOn:Binding(get:{model.toggle("MeshEnabled").wrappedValue},set:{value in
                model.toggle("MeshEnabled").wrappedValue=value
                if value {model.toggle("WaveEnabled").wrappedValue=false;model.toggle("NoiseEnabled").wrappedValue=false}
            })).disabled(!model.supportsMesh && !model.toggle("MeshEnabled").wrappedValue)
            if !model.supportsMesh {uiText("波浪网孔目前支持圆柱和椭圆柱。").font(.caption).foregroundStyle(.secondary)}
            if model.toggle("MeshEnabled").wrappedValue {
                if model.printerModel != "G1" {
                    Button(L("按喷嘴设置网孔参数")) {
                        let nozzle=Double(model.fields["Nozzle"] ?? "0.4") ?? 0.4
                        let width=Double(model.fields["W"] ?? "0.45") ?? 0.45
                        model.fields["MeshStrand"]=String(format:"%.3g",min(nozzle*0.5,width*0.8))
                        model.fields["MeshOpening"]=String(format:"%.3g",nozzle*2.5)
                        model.fields["MeshSpeed"]="5";model.dirty=true
                    }
                    uiText("此按钮仅设置料线厚度、网孔高度与网孔速度，不更改造型尺寸。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                row("每圈波数","MeshCount","个")
                row("网孔高度上限","MeshOpening")
                row("料线厚度","MeshStrand")
                row("接点压合量","MeshContactPress")
                row("接点搭接长度","MeshContactLength")
                ContextHelp("压合量缩小接点间距，不减少料线出料；上限为料线厚度的 25%。搭接长度沿轮廓测量，0 为原波形。接点连续走线，不停顿。")
                row("网孔速度上限","MeshSpeed","mm/s")
                ContextHelp("支持 Ginger G1、H2D、P1P、A1 与 A1 mini 的圆柱／椭圆柱。请关闭 EF；普通打印机同时受最大体积流量限速。")
                uiText("波数自动匹配半整数，让上下圈错开半波；网孔高度随总高度适配。首尾各一圈渐变接入。").interfaceFont(.caption).foregroundColor(.secondary)
                if let fit=model.preview?.mesh_fit, !model.dirty {
                    uiText(String(format:"实际：%g 波/圈 · 网孔 %.2f mm · %d 圈",fit.effective,fit.opening,fit.turns)).interfaceFont(.caption)
                }
                uiText("跨空段保持料线出料，不补满网孔。预览不模拟下垂；先用低速短样品验证粘接与喷嘴间隙。").interfaceFont(.caption).foregroundColor(.secondary)
            }
            Divider().padding(.vertical,4)
            uiText("路径波形").interfaceFont(.headline)
            Toggle(L("启用三角波"),isOn:Binding(get:{model.toggle("WaveEnabled").wrappedValue},set:{value in model.toggle("WaveEnabled").wrappedValue=value; if value {model.toggle("MeshEnabled").wrappedValue=false;model.toggle("NoiseEnabled").wrappedValue=false}})).disabled(["NonplanarCylinder","TripleVase","DoubleScroll","Crescent","SingleBud","CornerPipe","EggScroll","Wardrobe","TravelTest","Fern1060","Fern1060E","PipeScroll","PelletBottle","Hopper"].contains(model.fields["SourceMode"] ?? ""))
            if model.fields["SourceMode"] == "Crescent" {
                uiText("单弯月灯罩暂不叠加波形效果。").interfaceFont(.caption).foregroundColor(.secondary)
                if model.toggle("WaveEnabled").wrappedValue {Button(L("关闭三角波")){model.toggle("WaveEnabled").wrappedValue=false}}
            }
            if model.fields["SourceMode"] == "DoubleScroll" {
                uiText("双螺旋使用逐层往返走线，暂不叠加三角波。").interfaceFont(.caption).foregroundColor(.secondary)
                if model.toggle("WaveEnabled").wrappedValue {Button(L("关闭三角波")){model.toggle("WaveEnabled").wrappedValue=false}}
            }
            if model.fields["SourceMode"] == "TripleVase" {
                uiText("三螺旋花瓶已配套扩容走线，暂不叠加三角波。").interfaceFont(.caption).foregroundColor(.secondary)
                if model.toggle("WaveEnabled").wrappedValue {Button(L("关闭三角波")){model.toggle("WaveEnabled").wrappedValue=false}}
            }
            if model.fields["SourceMode"] == "NonplanarCylinder" {
                uiText("起伏口沿已配套非平面走线，第一版不叠加三角波。").interfaceFont(.caption).foregroundColor(.secondary)
                if model.toggle("WaveEnabled").wrappedValue {Button(L("关闭三角波")){model.toggle("WaveEnabled").wrappedValue=false}}
            }
            uiText("造型与 EF 之后处理墙体路径。底部和首层平面墙脚保持原样。").interfaceFont(.caption).foregroundColor(.secondary)
            if model.toggle("WaveEnabled").wrappedValue {
                row("波峰向外凸","WaveAmp")
                row("波谷向内凹","WaveNegAmp")
                row("每遍波数","WaveCount","个")
                if ["Cylinder","Ellipse","Cone"].contains(model.fields["SourceMode"] ?? "") {
                    Toggle(L("自动匹配波数"),isOn:model.toggle("WaveAutoFit"))
                    ContextHelp("切片时校核：1,2 交替匹配最近的半整数（40 → 39.5）；重复同一波形匹配整数。调整后更新输入框，并写入项目和 G-code。")
                    uiText(model.fields["SourceMode"] == "Ellipse" ? "波形沿椭圆周长均分，避免两端疏密不均；EF 改变周长时，毫米波距随之变化。":"按圆周等分波距；锥体或 EF 变径时，毫米波距随周长变化。起始接入和最终截断除外。").interfaceFont(.caption).foregroundColor(.secondary)
                    if let fit=model.preview?.wave_fit, !model.dirty {
                        uiText(String(format:"波数校核：%g → %g 波/遍。",fit.requested,fit.effective)).interfaceFont(.caption)
                        if fit.kind == "transitions" {
                            uiText("当前排列包含模式切换，过渡处不能保证等距。").interfaceFont(.caption).foregroundColor(.orange)
                        }
                    }
                }
                if model.fields["SourceMode"] == "Triple" {
                    uiText("三螺旋需较多波数。400 mm、3 圈示例可从 200 波预览；波数太少会跨过盘绕路径。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                row("前几遍保持原形","WaveStartLayer","遍")
                uiText("循环排列 · 0 原形 / 1 波形 A / 2 波形 B").interfaceFont(.subheadline)
                TextEditor(text:model.binding("WavePattern")).font(.system(.body,design:.monospaced)).frame(height:85).padding(6).background(Color(nsColor:.textBackgroundColor)).cornerRadius(6)
                if model.fields["SourceMode"] == "Triple" {
                    ContextHelp("排列循环：1 与 2 在主体区域固定错开半个波长，仅在接缝两侧各约两个波长内过渡。一遍指沿整个闭合造型走一遍。")
                } else {
                    ContextHelp("半整数波数让 1,2 沿整条路径连续交替，每圈自然错开半波，接缝不另补短波。整数配合 1,2 会保留相位切换；插入 0 或改变排列仍有过渡。")
                }
                Picker(L("Z 走法"),selection:model.binding("WaveZMode")) {
                    uiText("局部等高").tag("Source")
                    uiText("连续螺旋上升").tag("Continuous")
                }.id(appLanguage.code)
                ContextHelp(
                    "两种走法每遍波数相同。连续螺旋上升：沿路径持续升 Z。局部等高：波谷到波峰升 Z，波峰到波谷保持水平；接缝边走边升，不原地抬升。",
                    "三螺旋沿局部轮廓法线偏移。较大的波幅可能使相邻分支接近或交叉；先查看预览。流量按新路径长度与规划层高重新计算，不是材料变形模拟。"
                )
            }
        }
    }
}

struct ParameterPane: View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var model:Workbench
    @State private var effectsExpanded=false
    func row(_ label:String,_ key:String,_ unit:String="mm")->some View {NumberRow(model:model,label:label,key:key,unit:unit)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            PrinterSelector(model:model)
            NeutralSegments(titles:["造型","底部","补偿","打印"],values:[0,4,2,3],selection:$model.parameterTab).onChange(of:model.calibrationRevision){_ in model.parameterTab=2}
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    if model.parameterTab==0 {
                        ShapeControls(model:model)
                        if model.supportsEffects || model.hasActiveEffects {
                            Divider()
                            DisclosureGroup("表面效果",isExpanded:$effectsExpanded) {WaveControls(model:model)}
                                .onAppear {if model.hasActiveEffects {effectsExpanded=true}}
                        }
                    } else if model.parameterTab==4 {
                        BottomControls(model:model)
                    } else if model.parameterTab==2 {
                        CompensationControls(model:model).id("compensation")
                    } else if model.isBambu {
                        PrintQualityControls(model:model)
                        BambuControls(model:model)
                    } else {
                        PrintQualityControls(model:model)
                        PelletMaterialControls(model:model)
                        Divider()
                        uiText("温度").interfaceFont(.headline)
                        row("喷嘴温度","NT","°C");row("热床温度","BT","°C")
                        row("热区 1","ZONE1","°C");row("热区 2","ZONE2","°C");row("热区 3","ZONE3","°C")
                        Divider()
                        uiText("流量与速度").interfaceFont(.headline)
                        row("流量比例","FM","×")
                        if model.fields["SourceMode"] == "TravelTest" {
                            uiText("跨孔测试固定打印速度：9 mm/s（含裙边、首层和主体）。").interfaceFont(.caption).foregroundColor(.secondary)
                        } else {
                            speedRow("底部填充速度","BottomF");speedRow("外墙速度","WallF")
                        }
                        Divider()
                        uiText("位置与收尾").interfaceFont(.headline)
                        Toggle(L("左侧对齐裙边、首层与收尾"),isOn:model.toggle("AlignLeft"))
                        ContextHelp(model.fields["SourceMode"] == "DoubleScroll" && model.fields["DoubleLines"] == "3" ? "花瓶模式的首层起点、连续上升起点与顶部收尾固定在轮廓最左侧。":model.fields["SourceMode"] == "DoubleScroll" ? "双螺旋开启后，单线收尾位于左侧端点，双线接缝与收尾位于轮廓最左侧。":"最后不足一圈会走完整圈并减小上升量，总高度不变，挤出按实际间隙计算。三角波末遍回到接缝；关闭后沿用原起点与末尾相位。")
                        Divider()
                        uiText("1000 × 1000 mm 平台").interfaceFont(.subheadline)
                        row("模型中心 X","CX");row("模型中心 Y","CY")
                        if ["SingleBud","CornerPipe","EggScroll","Wardrobe","TravelTest","Fern1060","Fern1060E","PipeScroll","PelletBottle"].contains(model.fields["SourceMode"] ?? "") || (model.fields["SourceMode"] == "DoubleScroll" && model.fields["DoubleLines"] == "3") {
                            uiText("花瓶顶部自动整平").interfaceFont(.subheadline)
                            ContextHelp("按最后一周留下的实际间隙补齐顶部，再回抽抬 Z；不叠加末段减流。其他走线方式的收尾参数仍保留。")
                        } else {
                        Toggle(L("顶部减流收尾"),isOn:model.toggle("Finish"))
                        if model.toggle("Finish").wrappedValue {
                            row("收尾流量比例","FinishFlow","×")
                            if model.fields["SourceMode"] == "NonplanarCylinder" {uiText("沿完整起伏口沿逐渐减流，不叠加末段二次减流。").interfaceFont(.caption).foregroundColor(.secondary)}
                            if model.toggle("WaveEnabled").wrappedValue || model.toggle("MeshEnabled").wrappedValue || ["DoubleScroll","Crescent"].contains(model.fields["SourceMode"] ?? "") {
                                row("末段收尾长度","FinishLength")
                                uiText("沿最后一段路径逐渐减流，保持造型轮廓。").interfaceFont(.caption).foregroundColor(.secondary)
                            }
                        }
                        }
                        DisclosureGroup(L("回抽与颗粒挤出")) {
                            VStack(spacing:12) {
                                row("回抽长度","G1_RETRACT","E")
                                row("额外恢复挤出量","G1_RESTART_EXTRA","E")
                                row("回抽时抬升 Z","G1_Z_HOP")
                                speedRow("空移速度","G1_TRAVEL_F")
                                speedRow("回抽速度","G1_RETRACT_F")
                                speedRow("回抽恢复速度","G1_RESTORE_F")
                                Toggle(L("回抽时擦拭"),isOn:model.toggle("G1_WIPE"))
                                row("擦拭前回抽比例","G1_RETRACT_BEFORE_WIPE","%")
                                    .disabled(!model.toggle("G1_WIPE").wrappedValue)
                                uiText("0–100%；只调整回抽时机，总回抽量不变。也用于其他空移和打印收尾。").interfaceFont(.caption).foregroundColor(.secondary)
                                row("擦拭距离","G1_WIPE_DISTANCE")
                                ContextHelp("自动裙边启用擦拭时，首尾预留约 2 mm 净空，沿末段倒退擦拭后抬升，避开起点接头；实际料头需试打确认。")
                                row("挤出机每转体积","ROTATION_VOLUME","mm³")
                                row("颗粒挤出倍率","PF","×")

                            }.padding(.top,10)
                        }
                    }
                }.padding(.vertical,4)
            }
            .onAppear {revealCalibration(reader)}
            .onChange(of:model.calibrationActive){_ in revealCalibration(reader)}
            .onChange(of:model.calibrationRevision){_ in revealCalibration(reader)}
            }
        }.padding(16).frame(maxWidth:.infinity).disabled(model.busy)
    }
    private func revealCalibration(_ reader:ScrollViewProxy) {
        guard model.compensationReviewPending,!model.calibrationActive else{return}
        model.parameterTab=2
        DispatchQueue.main.async {
            reader.scrollTo("compensation",anchor:.top)
            model.compensationReviewPending=false
        }
    }
    func speedRow(_ label:String,_ key:String)->some View {
        NumberRow(model:model,label:label,key:key,unit:"mm/s")
    }

}

struct PathPreview: View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    let data:PreviewResult?
    let zLimit:Double
    let showTravel:Bool
    let showBed:Bool
    let mode:PreviewMode
    @Binding var zoom:Double
    let viewAction:Int
    @State private var yaw = -0.65
    @State private var pitch = 0.85
    @State private var savedYaw = -0.65
    @State private var savedPitch = 0.85
    @State private var top = false
    var body:some View {
        GeometryReader { geometry in
            Canvas { context,size in draw(context,size) }
            .contentShape(Rectangle())
            .background(CanvasScrollZoom{factor in zoom=min(30,max(0.25,zoom*factor))})
            .gesture(DragGesture().onChanged{v in top=false;yaw=savedYaw+v.translation.width*0.008;pitch=min(1.5,max(0.05,savedPitch+v.translation.height*0.006))}.onEnded{_ in savedYaw=yaw;savedPitch=pitch})
            .onChange(of:viewAction){value in top=value%3==1;yaw = -0.65;pitch=0.85;savedYaw=yaw;savedPitch=pitch}
            .onAppear {top=viewAction%3==1}
        }
    }
    private func draw(_ context:GraphicsContext,_ size:CGSize) {
                guard let data=data else{return}
                let points=data.segments
                guard !points.isEmpty else{return}
                let xs=points.flatMap{[$0[0],$0[3]]},ys=points.flatMap{[$0[1],$0[4]]}
                let whole=showBed && viewAction%3 != 2
                let cx=whole ? 500 : ((xs.min()!+xs.max()!)/2),cy=whole ? 500 : ((ys.min()!+ys.max()!)/2)
                let span=whole ? 1200 : max(xs.max()!-xs.min()!,ys.max()!-ys.min()!,data.height)*1.6
                let scale=min(size.width,size.height)/max(span,1)*zoom
                let angle=top ? 0.0 : yaw, elevation=top ? Double.pi/2 : pitch
                func project(_ x:Double,_ y:Double,_ z:Double)->CGPoint {
                    let x=x-cx,y=y-cy,z=z-(whole ? 0 : data.height*0.42)
                    let xx=x*cos(angle)-y*sin(angle),yy=x*sin(angle)+y*cos(angle)
                    return CGPoint(x:size.width/2+xx*scale,y:size.height*0.58-(yy*sin(elevation)+z*cos(elevation))*scale)
                }
                if showBed {
                    var grid=Path()
                    for v in stride(from:0.0,through:1000.0,by:100.0) {
                        grid.move(to:project(v,0,0));grid.addLine(to:project(v,1000,0));grid.move(to:project(0,v,0));grid.addLine(to:project(1000,v,0))
                    }
                    context.stroke(grid,with:.color(Color.white.opacity(0.25)),lineWidth:0.6)
                    var outline=Path();outline.move(to:project(0,0,0));outline.addLine(to:project(1000,0,0));outline.addLine(to:project(1000,1000,0));outline.addLine(to:project(0,1000,0));outline.closeSubpath()
                    context.stroke(outline,with:.color(Color.white.opacity(0.65)),lineWidth:1)
                    context.draw(uiText("0, 0").font(.caption).foregroundColor(.white.opacity(0.65)),at:project(0,0,0),anchor:.topLeading)
                }
                let heightColors=LayerHeightColors(heights:mode == .height ? (data.layer_heights ?? []):[])
                let bins=mode == .height ? heightColors.entries.count:48
                let limits=data.limits(mode,showTravel)
                var paths=Array(repeating:Path(),count:mode == .role || mode == .xray ? 5:bins+1)
                for (segmentIndex,s) in points.enumerated() {
                    let role=Int(s[6]);if role==4 && !showTravel {continue}
                    if min(s[2],s[5])>zLimit+0.00001{continue}
                    var start=Array(s[0...2]),end=Array(s[3...5])
                    if s[5]>zLimit && s[5]>s[2] {
                        let f:Double=(zLimit-s[2])/(s[5]-s[2])
                        for axis in 0..<3 {let delta:Double=s[axis+3]-s[axis];end[axis]=s[axis]+f*delta}
                    } else if s[2]>zLimit && s[2]>s[5] {
                        let f:Double=(zLimit-s[5])/(s[2]-s[5])
                        for axis in 0..<3 {let delta:Double=s[axis]-s[axis+3];start[axis]=s[axis+3]+f*delta}
                    }
                    let index:Int
                    if mode == .role || mode == .xray {index=role}
                    else if role==4 && mode != .speed {index=bins}
                    else if mode == .height {index=heightColors.index(data.displayLayerHeight(segmentIndex)) ?? bins}
                    else {
                        let span=limits[1]-limits[0]
                        let fraction=span>0.0000001 ? (s[mode.index]-limits[0])/span : 0.5
                        index=min(bins-1,max(0,Int((fraction*Double(bins-1)).rounded())))
                    }
                    paths[index].move(to:project(start[0],start[1],start[2]));paths[index].addLine(to:project(end[0],end[1],end[2]))
                }
                if mode == .xray {
                    for role in [4,0,1,2,3] {
                        context.stroke(paths[role],with:.color(Color(white:0.95).opacity(role==4 ? 0.15:role==0 ? 0.3:0.65)),style:StrokeStyle(lineWidth:role==4 ? 0.6:0.85,dash:role==4 ? [3,3]:[]))
                    }
                } else if mode == .role {
                    let colors:[Color]=previewRoleColors
                    for role in [4,0,1,2,3] {
                        context.stroke(paths[role],with:.color(colors[role].opacity(role==4 ? 0.5 : 0.9)),style:StrokeStyle(lineWidth:role==4 ? 0.6:0.9,dash:role==4 ? [3,3]:[]))
                    }
                } else {
                    context.stroke(paths[bins],with:.color(Color.gray.opacity(0.5)),style:StrokeStyle(lineWidth:0.6,dash:[3,3]))
                    for index in 0..<bins {
                        let rgb=mode == .height ? heightColors.entries[index].rgb:previewMetricRGB(Double(index)/Double(bins-1))
                        context.stroke(paths[index],with:.color(Color(red:rgb[0],green:rgb[1],blue:rgb[2])),lineWidth:1.2)
                    }
                }

    }

}

struct PrintStatistics:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    let summary:PreviewResult.Summary
    private var minutes:Int {max(1,Int(ceil(summary.motion_minutes)))}
    func number(_ value:String)->some View {
        uiText(value).interfaceFixedFont(size:28,weight:.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
    }
    func unit(_ value:String)->some View {uiText(value).interfaceFont(.subheadline).foregroundColor(.secondary)}
    func card<Value:View>(_ title:String,_ icon:String,_ detail:String,_ footnote:String,@ViewBuilder value:()->Value)->some View {
        VStack(alignment:.leading,spacing:10) {
            Label(L(title),systemImage:icon).interfaceFont(.subheadline).foregroundColor(.secondary)
            value().frame(height:36,alignment:.leading)
            VStack(alignment:.leading,spacing:6) {
                uiText(detail)
                uiText(footnote)
            }.interfaceFont(.caption).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.75).frame(height:34,alignment:.topLeading)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(16).glassCard()
    }
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            card(summary.assembly == nil ? "材料用量" : "当前件用料","scalemass",String(format:"模型 %.1f g · 裙边 %.1f g · 额外 %.1f g",summary.model_mass_g,summary.skirt_mass_g,summary.extra_mass_g),String(format:"密度 %.3g g/cm³ · 体积 %.1f cm³",summary.density_g_cm3,summary.volume_mm3/1000)) {
                HStack(alignment:.firstTextBaseline,spacing:5) {number(String(format:"%.1f",summary.mass_g));unit("g")}
            }
            if let assembly=summary.assembly {
                card("整套六件预计用料","shippingbox","①至⑥各一件 · 含各件额外耗料","不含⑦、定位套和管材 · 轮廓积分预估") {
                    HStack(alignment:.firstTextBaseline,spacing:5) {unit("约");number(String(format:"%.0f",assembly.mass_g));unit("g")}
                }
            }

            if let total=summary.assembly?.motion_minutes {
                let duration=max(1,Int(ceil(total)))
                card("整套六件预计时间","clock.arrow.circlepath","①至⑥各打印一次的累计用时","不含预热、调平、加减速及换件") {
                    HStack(alignment:.firstTextBaseline,spacing:5) {
                        unit("约");number("\(duration/60)");unit("小时")
                        number("\(duration%60)");unit("分")
                    }
                }
            }
            card(summary.assembly == nil ? "预计打印时间" : "当前件预计时间","clock","包含打印与空移的指令用时","不含预热、调平和加减速影响") {
                HStack(alignment:.firstTextBaseline,spacing:5) {
                    if minutes>=60 {number("\(minutes/60)");unit("小时")}
                    number("\(minutes%60)");unit("分钟")
                }
            }
        }
    }
}

struct ContentView:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var model=Workbench()
    @State private var dropTargeted=false
    @State private var details=false
    @State private var calibrationLoaded=false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var timeline=PathTimeline()
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(nsImage:NSImage(contentsOf:Bundle.main.url(forResource:"Logo149VectorWhite",withExtension:"pdf")!)!)
                    .renderingMode(.template).resizable().scaledToFit().foregroundStyle(.primary)
                    .frame(width:68,height:44).padding(.horizontal,12).frame(height:60).glassCard().accessibilityLabel(L("149 标志"))
                HStack(spacing:12) {
                    NeutralSegments(titles:["建模","校准"],values:[false,true],selection:$model.calibrationActive).frame(width:160)
                    Spacer()
                    if !model.calibrationActive {
                        Button(action:model.generate) {Label(L(model.busy ? "切片中…":"切片"),systemImage:"square.3.layers.3d")}
                            .buttonStyle(.borderedProminent).tint(.gray).disabled(!model.canSlice).keyboardShortcut("r",modifiers:.command)
                        Button(action:model.requestSend) {Label {uiText(model.sendTitle)} icon:{Image(nsImage:FabricationSymbol.image)}}
                            .disabled(!model.canSend)
                    }
                }.padding(.horizontal,16).frame(height:60).glassCard()
            }.padding(.horizontal,10).padding(.top,10)
            if let error=model.error {
                HStack(alignment:.top) {
                    Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(L(error)).font(.callout).lineLimit(3).textSelection(.enabled).help(L(error))
                    Spacer(minLength:8)
                    Button {model.error=nil} label:{Image(systemName:"xmark")}.buttonStyle(.plain).help(L("收起提示"))
                }.padding(12).background(Color.orange.opacity(0.1))
            }
            ZStack {
                HStack(spacing:0) {
                    ParameterPane(model:model).id(appLanguage.code).frame(width:350).glassCard().padding(10)
                    previewWorkspace.frame(minWidth:500,maxWidth:.infinity,maxHeight:.infinity).glassCard().padding(.vertical,10).padding(.trailing,10)
                }.opacity(model.calibrationActive ? 0:1).allowsHitTesting(!model.calibrationActive).accessibilityHidden(model.calibrationActive)
                if calibrationLoaded {ZStack {CalibrationGlassBackground(sidebarCollapsed:model.calibrationSidebarCollapsed,presentation:model.calibrationPresentation);CalibrationWorkspace(model:model,active:model.calibrationActive).id(model.calibrationLoadID)
                    if model.calibrationLoading || model.calibrationLoadError != nil {
                        VStack(spacing:12) {
                            if let error=model.calibrationLoadError {
                                Image(systemName:"exclamationmark.triangle").font(.title2)
                                Text(error).multilineTextAlignment(.center)
                                Button("重新加载") {model.calibrationLoadError=nil;model.calibrationLoading=true;model.calibrationLoadID=UUID()}
                            } else {
                                ProgressView()
                                Text("正在加载校准工作区…").foregroundStyle(.secondary)
                            }
                        }.padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    .opacity(model.calibrationActive ? 1:0).allowsHitTesting(model.calibrationActive).accessibilityHidden(!model.calibrationActive)}
            }
        }
        .interfaceFont(.body)
        .toolbar {
            ToolbarItemGroup(placement:.automatic) {
                DeviceToolbarButtons(model:model).labelStyle(.iconOnly)
            }
        }
        .labelStyle(.titleAndIcon)
        .sheet(isPresented:$model.showSendSheet){GingerPrintSheet(model:model)}
        .focusedSceneObject(model)
        .toggleStyle(CapsuleSwitchStyle())
        .onAppear{model.scheduleModelPreview(immediate:true)}
        .onChange(of:model.preview?.sha256){_ in if let p=model.preview{timeline.load(p)}}
        .onChange(of:model.fields){_ in
            if !model.busy {model.error=nil};model.persistDraft()
            if !model.calibrationActive {model.scheduleModelPreview()}
        }
        .onChange(of:model.calibrationActive){active in
            timeline.playing=false
            if active {calibrationLoaded=true;model.suspendModelPreview()}else{model.scheduleModelPreview(immediate:true)}
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in model.flushDraft()}
        .onChange(of:scenePhase){phase in if phase != .active {timeline.playing=false}}
        .background(WindowGlass()).frame(minWidth:980,minHeight:680)
    }
    private var previewWorkspace:some View {
        VStack(spacing:10) {
            HStack(spacing:12) {
                NeutralSegments(titles:["模型","切片结果"],values:[true,false],selection:$model.showingModel,disabledValues:model.preview==nil ? [false]:[]).frame(width:165)
                Spacer(minLength:4)
                if model.modelRefreshing {ProgressView().controlSize(.small).help(L("正在更新预览"))}
                if !model.showingModel && model.dirty {Label(L("需重新切片"),systemImage:"circle.fill").font(.caption).foregroundStyle(.orange)}
                if !model.showingModel {displayMenu}
                Menu {
                    Button(L("立体视角")){model.cameraAction(5)}
                    Button(L("俯视")){model.cameraAction(1)}
                    Button(L("正视")){model.cameraAction(3)}
                    Button(L("左视")){model.cameraAction(4)}
                    Divider()
                    Toggle(L("平移模式"),isOn:$model.panMode)
                    Button(L("复位")){model.cameraAction(0)}
                    Button(L("适合窗口")){model.cameraAction(2)}
                    if !model.showingModel {Button(L("查看整个平台")){model.showBed=true;model.cameraAction(6)}}
                } label:{Label(L("视角"),systemImage:"rotate.3d")}.fixedSize()
            }.controlSize(.small)
            ZStack(alignment:.top) {
                Color(nsColor:.underPageBackgroundColor)
                if model.showingModel,let geometry=model.modelGeometry {
                    ModelPreview(model:geometry,viewAction:model.beadViewAction,zoom:$model.previewZoom,panMode:model.panMode,source:model.fields["SourceMode"] ?? "")
                        .opacity(model.modelNeedsUpdate ? 0.35:1)
                } else if !model.showingModel,let preview=model.preview {
                    ZStack {
                        Color(white:0.063)
                        BeadPreview(data:preview,zLimit:Double.greatestFiniteMagnitude,showTravel:model.showTravel,showBed:model.showBed,mode:model.previewMode,viewAction:model.beadViewAction,zoom:$model.previewZoom,visibleCount:timeline.cursor.end,segmentFraction:timeline.cursor.fraction,nozzlePoint:timeline.showNozzle ? timeline.cursor.point:nil,asLines:!model.showBeads,panMode:model.panMode)
                    }.opacity(model.dirty ? 0.5:1)
                }
                if model.modelGeometry==nil && model.modelError==nil {ProgressView(L("正在准备预览…")).frame(maxWidth:.infinity,maxHeight:.infinity)}
                if let error=model.modelError {
                    Label(L(error),systemImage:"exclamationmark.circle").font(.callout).lineLimit(3).textSelection(.enabled).padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(12)
                }
                if model.busy {ProgressView(L("正在切片…")).padding(20).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).frame(maxWidth:.infinity,maxHeight:.infinity)}
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(dropTargeted ? Color.accentColor:.clear,lineWidth:2))
            .onDrop(of:[UTType.fileURL],isTargeted:$dropTargeted){model.receiveModelDrop($0)}
            if model.showingModel,let geometry=model.modelGeometry {
                HStack {
                    Label(String(format:"%.1f × %.1f × %.1f mm",geometry.dimensions[0],geometry.dimensions[1],geometry.dimensions[2]),systemImage:"ruler").monospacedDigit()
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary).opacity(model.modelNeedsUpdate ? 0.5:1)
            }
            if !model.showingModel,let preview=model.preview {sliceDetails(preview)}
        }.padding(14)
    }
    private var displayMenu:some View {
        Menu {
                Picker(L("显示模式"),selection:$model.previewMode) {ForEach(PreviewMode.allCases) {uiText($0.rawValue).tag($0)}}
                Divider()
                Toggle(L("料道"),isOn:$model.showBeads)
                Toggle(L("空移"),isOn:$model.showTravel)
                Toggle(L("打印平台"),isOn:$model.showBed)
        } label:{Label(L("显示"),systemImage:"eye")}.fixedSize()
    }
    private func sliceDetails(_ preview:PreviewResult)->some View {
        VStack(spacing:8) {
            PlaybackControls(timeline:timeline,enabled:!model.calibrationActive && !model.busy && !model.dirty)
            HStack(spacing:18) {
                Label(String(format:"%.1f g",preview.summary.mass_g),systemImage:"scalemass")
                Label(String(format:"%.0f min",ceil(preview.summary.motion_minutes)),systemImage:"clock")
                    .help(L("不含预热、调平和加减速影响"))
                if let d=preview.summary.model_dimensions_mm,d.count==3 {Text(String(format:"%.1f × %.1f × %.1f mm",d[0],d[1],d[2])).foregroundStyle(.secondary)}
                Spacer()
                Button {details.toggle()} label:{Label(L("详情"),systemImage:details ? "chevron.up":"chevron.down")}.buttonStyle(.plain)
            }.font(.callout).monospacedDigit().opacity(model.dirty ? 0.5:1)
            if model.previewMode != .role && model.previewMode != .xray {
                if model.previewMode == .height {LayerHeightLegend(scale:LayerHeightColors(heights:preview.layer_heights ?? []))}
                else {MetricLegend(mode:model.previewMode,limits:preview.limits(model.previewMode,model.showTravel))}
            }
            if details {
                ScrollView {VStack(alignment:.leading,spacing:8) {PrintStatistics(summary:preview.summary);uiText(preview.info).font(.caption).textSelection(.enabled);uiText(model.previewMode.detail).font(.caption).foregroundStyle(.secondary)}}.frame(maxHeight:180)
            }
        }
    }
}

struct ProjectCommands:Commands {
    @FocusedObject private var model:Workbench?
    @ObservedObject private var language=AppLanguage.shared
    var body:some Commands {
        CommandGroup(replacing:.newItem) {
            Button(L(model?.calibrationActive==true ? "打开测量记录…":"打开项目…")){model?.openWorkspaceDocument()}.keyboardShortcut("o").disabled(model==nil || model?.busy==true)
            Button(L(model?.calibrationActive==true ? "保存测量记录":"保存项目")){model?.saveWorkspaceDocument()}.keyboardShortcut("s").disabled(model==nil || model?.busy==true)
            Button(L("另存为…")){model?.saveWorkspaceDocumentAs()}.keyboardShortcut("s",modifiers:[.command,.shift]).disabled(model==nil || model?.busy==true)
            Button(L("导入模型…")){model?.importModel()}.keyboardShortcut("i").disabled(model?.canImport != true)
            Divider()
            if model?.calibrationActive==true {Button(L("导出测量 CSV…")){model?.requestCalibration("csv")}.keyboardShortcut("e",modifiers:[.command,.shift])}
            else {Button(L("导出 G-code…")){model?.exportGcode()}.keyboardShortcut("e",modifiers:[.command,.shift]).disabled(model==nil || model?.busy==true || model?.dirty != false || model?.preview==nil)}
        }
    }
}

#if !TESTING
@main
struct G1MiniApp:App {
    @ObservedObject private var appLanguage=AppLanguage.shared
    init() {
        // Remove the old app-only graphite override; use the system accent.
        UserDefaults.standard.removeObject(forKey:"AppleAccentColor")
        UserDefaults.standard.removeObject(forKey:"AppleHighlightColor")
        NSApplication.shared.appearance=nil
        NeutralInputAppearance.install()
        DispatchQueue.main.async {
            if let url=Bundle.main.url(forResource:"149",withExtension:"icns") {NSApp.applicationIconImage=NSImage(contentsOf:url)}
        }
    }
    var body:some Scene {
        WindowGroup("149 Slicer"){ContentView()}.windowStyle(.titleBar).commands{ProjectCommands();WorkspaceCommands()}
        Window(L("G1 打印机"),id:"printer"){PrinterWindow()}.defaultSize(width:1100,height:780)
        Window(L("颗粒烘干机"),id:"pellet-dryer"){PelletDryerWindow()}.defaultSize(width:1000,height:780)
        Window(L("打印监控"),id:"camera-monitor"){CameraMonitorWindow()}.defaultSize(width:1100,height:800)
        Window(L("AMS-HT 烘干机"),id:"ams-ht"){AMSDryingWindow()}.defaultSize(width:1080,height:650)
    }
}
#endif
