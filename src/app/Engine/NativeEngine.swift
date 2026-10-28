import Foundation
import CryptoKit

struct NativeSliceResult {
    let gcode:String,project:NativeSliceProject,preview:NativePreview,metadata:[String:Any],bambu:NativeBambu.Plan?
    let model:SliceShape
    var dictionary:[String:Any] {
        var result=metadata;result["gcode"]=gcode;result["project"]=project.dictionary;result["segments"]=preview.segments;result["beads"]=preview.beads;result["layers"]=preview.layers.map{["start":$0.start,"end":$0.end,"z":$0.z] as [String:Any]};result["layer_heights"]=preview.layerHeights
        if let bambu=bambu {result["_bambu_config"]=bambu.config;result["_bambu_model_id"]=bambu.modelID};return result
    }
    func write(to folder:URL) throws {
        try gcode.write(to:folder.appendingPathComponent("preview.gcode"),atomically:true,encoding:.utf8)
        if let bambu=bambu {try NativeBambu.package(project:project,plan:bambu,stats:metadata["summary"] as! [String:Any],gcode:gcode,segments:preview.segments,to:folder.appendingPathComponent("preview.gcode.3mf"))}
    }
}

struct NativePreparedModel {let key:Data;let shape:SliceShape}

final class NativeSliceEngine {
    typealias G=SliceGeometry
    let resources:URL,shapes:URL,stepHelper:URL?
    private let defaults:[String:Any],materials:[String:[String:Any]],lock=NSLock()
    private var reference:WardrobeReference?,lengthsCache=[Data:[Double]](),lengthsOrder=[Data]()
    init(resources:URL,stepHelper:URL?=nil) throws {
        self.resources=resources;shapes=resources.appendingPathComponent("g1mini");self.stepHelper=stepHelper
        defaults=try NativeBambu.readObject(shapes.appendingPathComponent("defaults.json"))
        let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:shapes.appendingPathComponent("pellet_materials.json"))) as! [[String:Any]]
        materials=Dictionary(uniqueKeysWithValues:catalog.map{($0["id"] as! String,$0)})
    }
    private func configured(_ raw:[String:Any],forPreview:Bool=false) throws -> (NativeSliceProject,SliceParameters) {
        var project=try NativeSliceProject(raw,defaults:defaults),shape=project.shape
        let mode=shape.text("SourceMode"),selected=project.machine.text("PrinterModel"),pellet=project.material.text("PelletMaterial")
        guard selected != "G1" || materials[pellet] != nil else {throw SliceFailure("未知的颗粒材料，请在打印页重新选择材料。")}
        if shape.flag("EdgeCalibrationEnabled") {shape["_EdgeFirstFlow"]=project.machine["PF"]*project.machine["FM"]*project.machine["F0"]}
        if selected != "G1" {if !forPreview {_=try NativeBambu.validate(project)};shape.values["_FilamentMode"]=true}
        func hasEffects(_ keys:[String]=["WaveEnabled","MeshEnabled","NoiseEnabled","NoiseZEnabled"])->Bool {keys.contains{project.process.flag($0)}}
        if ["Fern1060","Fern1060E"].contains(mode) {
            guard selected=="G1" else {throw SliceFailure("圆拱支架目前适用于G1的一米平台。")}
            guard !hasEffects() else {throw SliceFailure("圆拱支架需保持已确认轮廓，请关闭叠加效果。")}
            project.machine.set(["CX":500,"CY":500,"SKIRT_AUTO":false,"START_ENABLE":false,"Finish":false])
        }
        if mode=="Hopper" {guard selected=="G1" else {throw SliceFailure("可调高料桶使用 Ginger G1 一米平台。")};_=try G.hopperReport(shape,density:project.material["Density"])}
        if ["PelletBottle","Hopper"].contains(mode) && hasEffects() {throw SliceFailure("料瓶请关闭叠加效果，保持连续圆形单墙。")}
        if mode=="PipeScroll" && hasEffects() {throw SliceFailure("插管型需保持原卷芯配合，请关闭波形、网孔和随机波。")}
        if mode=="TravelTest" {
            guard selected=="G1" else {throw SliceFailure("跨孔空移测试目前适用于 G1；请使用与正式件相同的机器和材料。")}
            project.process.set(["WaveEnabled":false,"MeshEnabled":false,"NoiseEnabled":false]);project.machine.set(["CX":500,"CY":500,"G1_Z_HOP":6,"SKIRT_AUTO":true,"START_ENABLE":false,"F":540,"WallF":540,"BottomF":540,"SKIRT_F":540])
        }
        if mode=="Crescent" && hasEffects(["WaveEnabled","MeshEnabled"]) {throw SliceFailure("单弯月灯罩暂不叠加波形，请关闭三角波与波浪网孔。")}
        if mode=="SingleBud" && hasEffects(["WaveEnabled","MeshEnabled","NoiseEnabled"]) {throw SliceFailure("单螺旋花蕾已配套变截面走线，请关闭三角波、网孔与随机波。")}
        if ["Wardrobe","EggScroll","CornerPipe"].contains(mode) {
            let label=mode=="Wardrobe" ? "挂衣体":mode=="EggScroll" ? "蛋形双卷":"墙角连接管"
            guard !hasEffects(["WaveEnabled","MeshEnabled","NoiseEnabled"]) else {throw SliceFailure(label+"需要保持孔径和料道间距，请关闭三角波、网孔和随机波。")}
            guard selected=="G1" else {throw SliceFailure(label+"目前适用于 G1 颗粒打印机。")}
            guard abs(project.machine["PF"]*project.machine["FM"]-1)<=1e-8,project.machine["F0"]<=1 else {throw SliceFailure("连接孔及料道间距按标称线宽校核；请保持颗粒系数 × 总流量为 1，首层流量不大于 1。")}
        }
        return (project,shape)
    }
    private func geometryKey(_ project:NativeSliceProject,_ shape:SliceParameters) throws -> Data {
        try JSONSerialization.data(withJSONObject:["shape":shape.values,"process":project.process.values],options:[.sortedKeys])
    }
    private func buildShape(_ shape:SliceParameters,_ process:SliceParameters) throws -> SliceShape {
        try SliceComputation.check()
        if shape.text("SourceMode")=="Wardrobe",reference==nil {reference=try WardrobeReference(resources:shapes)}
        return try G.applyNoise(G.applyMesh(G.applyWaves(G.makeShape(shape,resources:shapes,stepHelper:stepHelper,wardrobeReference:reference),process),process),process)
    }
    func prepareModel(_ raw:[String:Any]) throws -> NativePreparedModel {
        lock.lock();defer{lock.unlock()}
        let (project,shape)=try configured(raw,forPreview:true)
        return NativePreparedModel(key:try geometryKey(project,shape),shape:try buildShape(shape,project.process))
    }
    func generate(_ raw:[String:Any],prepared:NativePreparedModel?=nil) throws -> NativeSliceResult {
        lock.lock();defer{lock.unlock()}
        let started=Date();var (project,shape)=try configured(raw)
        let mode=shape.text("SourceMode"),selected=project.machine.text("PrinterModel"),key=try geometryKey(project,shape)
        // External meshes are read again even if the file path has not changed.
        var model=try prepared?.key==key && mode != "Imported" ? prepared!.shape:buildShape(shape,project.process)
        let mesh=model.details["mesh"] as? [String:Any],wave=model.details["wave_fit"] as? [String:Any]
        if let fitted=mesh?["effective"] {project.process.values["MeshCount"]=fitted};if let fitted=wave?["effective"] {project.process.values["WaveCount"]=fitted}
        var bambu:NativeBambu.Plan?,final:String
        if selected=="G1" {final=try G1Exporter(settings:project.machine,resources:resources).export(model.gcode).gcode}
        else {let plan=try NativeBambu.plan(model,project:project,resources:resources);bambu=plan;final=plan.preview}
        if mode=="TravelTest" {
            for r in try SliceGcode.records(G.markedBody(final)).0 {for axis in ["X","Y"] {if let value=r.after[axis],value<3 || value>997 {throw SliceFailure("测试路径超出1000 mm平台。")}}}
            let m=project.machine;model.info+="\n本次回抽 \(G.fmt(m["G1_RETRACT"])) mm³；重启额外补料 \(G.fmt(m["G1_RESTART_EXTRA"])) mm³；空移 \(G.fmt(m["G1_TRAVEL_F"]/60)) mm/s。固定平台居中，外围一圈裙边；主体与裙边9 mm/s，不叠加额外起始减流。"
        }
        let annotation=try annotate(final,project:project);final=annotation.0;model.info+=annotation.1
        let density=try G.materialStats([],volume:0,material:project.material)["density_g_cm3"]!,densityText=String(format:"%.6g",density)
        final=try SliceGcode.settingsMetadata(final,key:"filament_density"){_ in densityText+","+densityText}
        let preview=try G.previewData(final,model:model)
        if mode=="NonplanarCylinder" || project.process.flag("MeshEnabled") {
            let peak=preview.segments.filter{$0[6] != 4}.map{s -> Double in let d=G.distance3(SlicePoint(s[0],s[1],s[2]),SlicePoint(s[3],s[4],s[5]));return d>0 ? abs(s[5]-s[2])*s[9]/d:0}.max() ?? 0
            model.info+=String(format:"\n按当前指令速度估计的打印 Z 轴峰值速度：%.2f mm/s。",peak)
        }
        let mass=try G.materialStats(preview.segments,volume:preview.volume,material:project.material)
        var summary=mass.mapValues{$0 as Any};summary.merge(["segments":preview.segments.count,"volume_mm3":G.rounded(preview.volume,1),"path_mm":G.rounded(preview.length,1),"motion_minutes":G.rounded(preview.motionSeconds/60,1),"model_dimensions_mm":G.modelDimensions(preview)]){_,new in new}
        if mode=="Wardrobe" && shape["WardLayout"]==2 && !shape.flag("WardBedTest") {
            var values=shape.values;values.removeValue(forKey:"WardPart");let key=try JSONSerialization.data(withJSONObject:values,options:[.sortedKeys])
            let lengths:[Double]
            if let cached=lengthsCache[key] {lengths=cached}else{lengths=try WardrobeSliceSections.quarterLengths(shape,reference:reference!);lengthsCache[key]=lengths;lengthsOrder.append(key);if lengthsOrder.count>12 {lengthsCache.removeValue(forKey:lengthsOrder.removeFirst())}}
            summary["assembly"]=try G.frameMass(shape,material:project.material,current:mass,segments:preview.segments,lengths:lengths)
        }
        if mode=="Hopper" {summary["hopper_capacity"]=try G.hopperReport(shape,density:project.material["Density"])}
        if var plan=bambu {final=try NativeBambu.export(project,plan:&plan,stats:summary,layerCount:preview.layers.count);bambu=plan}
        summary["compute_seconds"]=G.rounded(Date().timeIntervalSince(started),2)
        var info=model.info;for (source,target) in [("NonplanarCylinder","起伏口沿圆柱"),("Cylinder","参数圆柱"),("Ellipse","椭圆柱"),("Cone","锥形灯罩")] {info=info.replacingOccurrences(of:source,with:target)}
        var metadata:[String:Any]=["ok":true,"machine_name":selected,"bed_size":bambu?.profile.bed ?? [1000,1000,1000],"preview_schema":2,"ranges":preview.ranges,"height":model.parameters["CH"],"summary":summary,"flow_report":bambu?.flowReport as Any? ?? NSNull(),"wave_fit":wave as Any? ?? NSNull(),"mesh_fit":mesh as Any? ?? NSNull(),"noise_fit":model.details["noise_fit"] ?? NSNull(),"lamp_reference":NSNull(),"info":info,"sha256":SHA256.hash(data:Data(final.utf8)).map{String(format:"%02x",$0)}.joined()]
        if let crescent=model.details["crescent"] as? [String:Any] {metadata["lamp_reference"]=["center":[project.machine["CX"],project.machine["CY"],model.parameters["CH"]/2],"diameter":crescent["bulb_diameter"]!]}
        return NativeSliceResult(gcode:final,project:project,preview:preview,metadata:metadata,bambu:bambu,model:model)
    }
    private func annotate(_ input:String,project:NativeSliceProject) throws -> (String,String) {
        let key=project.material.text("PelletMaterial")
        if project.machine.text("PrinterModel") != "G1" || key=="polymaker_petg1000" {return (input,"")}
        let material=materials[key]!,name=key=="custom" ? "Custom pellet":material["name"] as! String,kind=key=="cafblo_rsd038_4r0001" ? "CA":"Custom";var gcode=input
        for (setting,value) in [("filament_type",kind),("filament_settings_id",name),("filament_vendor",kind=="CA" ? "DAICEL":"Custom")] {
            let encoded=setting=="filament_settings_id" ? String(decoding:try JSONEncoder().encode(value),as:UTF8.self):value
            gcode=try SliceGcode.settingsMetadata(gcode,key:setting){equal in encoded+(equal ? ";":",")+encoded}
        }
        gcode="; PELLET_MATERIAL="+key+"\n"+gcode
        var info=String(format:"\n颗粒材料：%@；密度 %.3f g/cm³。",name,project.material["Density"])
        if kind=="CA" {info+="\nCAFBLO 透明微蓝：三热区参考 210/220/230°C。喷嘴、热床和速度为可调整试验值，非实测材料上限。";if ["NT","ZONE1","ZONE2","ZONE3"].map({project.machine[$0]}).max()!>240 {info+="\n注意：当前温度超过 240°C；厂家提示可能起泡或降解。"}}
        return (gcode,info)
    }
}
