import Foundation

extension NativeBambu {
    static func profileRoot() throws -> URL {
        let roots=[FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BambuStudio/system/BBL"),studio.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/profiles/BBL")]
        guard let root=roots.first(where:{FileManager.default.fileExists(atPath:$0.appendingPathComponent("machine/Bambu Lab H2D 0.4 nozzle.json").path)}) else {throw SliceFailure("需要安装并打开一次 Bambu Studio，下载这四种机型的官方配置。")};return root
    }
    static func readObject(_ url:URL) throws -> [String:Any] {guard let value=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any] else {throw SliceFailure("配置文件格式无效："+url.lastPathComponent)};return value}
    static func flatten(_ root:URL,group:String,name:String,stack:[String]=[]) throws -> [String:Any] {
        guard !stack.contains(name),stack.count<=20 else {throw SliceFailure("官方预设继承循环。")}
        guard !name.contains("/"),!name.contains("\\") else {throw SliceFailure("官方预设名称无效。")}
        let raw=try readObject(root.appendingPathComponent(group+"/"+name+".json"));var result=[String:Any]()
        if let parent=raw["inherits"] as? String,!parent.isEmpty {result=try flatten(root,group:group,name:parent,stack:stack+[name])}
        for include in raw["include"] as? [String] ?? [] {result.merge(try flatten(root,group:group,name:include,stack:stack+[name])){_,new in new}}
        result.merge(raw){_,new in new};result.removeValue(forKey:"inherits");result.removeValue(forKey:"include");return result
    }
    static func writeBox(_ url:URL,bounds:[Double],height:Double) throws {
        let x0=bounds[0],y0=bounds[1],x1=bounds[2],y1=bounds[3],vertices=[0.0,height].flatMap{z in [y0,y1].flatMap{y in [x0,x1].map{x in SlicePoint(x,y,z)}}},faces=[[0,2,1],[1,2,3],[4,5,6],[5,7,6],[0,1,4],[1,5,4],[2,6,3],[3,6,7],[0,4,2],[2,4,6],[1,3,5],[3,7,5]]
        var data=Data("149 startup envelope only".utf8);data.append(Data(repeating:32,count:80-data.count))
        func append<T>(_ value:T) {var value=value;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
        append(UInt32(12).littleEndian)
        for face in faces {let values:[Float]=[0,0,0]+face.flatMap{index -> [Float] in [Float(vertices[index].x),Float(vertices[index].y),Float(vertices[index].z)]};for value in values {append(value.bitPattern.littleEndian)};append(UInt16(0))}
        try data.write(to:url)
    }
    static func officialGcode(_ project:NativeSliceProject,plan:inout Plan) throws -> String {
        guard FileManager.default.fileExists(atPath:studio.path) else {throw SliceFailure("请先安装 Bambu Studio，用于生成官方启动和结束流程。")}
        let root=try profileRoot(),m=project.machine,p=plan.profile,nd=String(format:"%.1f",m["Nozzle"]),machine=try flatten(root,group:"machine",name:p.name+" "+nd+" nozzle")
        let processName=nd=="0.4" ? "0.20mm Standard @BBL "+p.tag:nd=="0.6" ? "0.30mm Standard @BBL "+p.tag+" 0.6 nozzle":"0.40mm Standard @BBL "+p.tag+" 0.8 nozzle"
        var process=try flatten(root,group:"process",name:processName)
        let label="Generic "+m.text("FilamentType"),choices=[label+" @BBL "+p.tag,label+" @base"]
        guard let name=choices.first(where:{FileManager.default.fileExists(atPath:root.appendingPathComponent("filament/"+$0+".json").path)}) else {throw SliceFailure("本机 Bambu Studio 未安装对应材料的官方预设。")}
        var filament=try flatten(root,group:"filament",name:name)
        filament.merge(["nozzle_temperature":[G.fmt(m["NT"])],"nozzle_temperature_initial_layer":[G.fmt(m["NT"])],"filament_diameter":["1.75"],"filament_density":[G.fmt(project.material["Density"])],"filament_flow_ratio":["1"],"filament_max_volumetric_speed":[G.fmt(m["MaxVolumetric"])]] as [String:Any]){_,new in new}
        for key in ["hot_plate_temp","textured_plate_temp"] {filament[key]=[G.fmt(m["BT"])];filament[key+"_initial_layer"]=[G.fmt(m["BT"])]}
        process.merge(["sparse_infill_density":"0%","top_shell_layers":"0","bottom_shell_layers":"1","wall_loops":"1","enable_prime_tower":"0","brim_type":"no_brim","skirt_loops":"0","enable_support":"0","timelapse_type":"0","spiral_mode":"0","layer_height":G.fmt(m["Nozzle"]/2),"initial_layer_print_height":G.fmt(m["Nozzle"]/2),"line_width":G.fmt(m["Nozzle"]*1.125),"outer_wall_line_width":G.fmt(m["Nozzle"]*1.125),"initial_layer_line_width":G.fmt(m["Nozzle"]*1.125),"outer_wall_speed":[G.fmt(m["WallF"]/60)],"initial_layer_speed":[G.fmt(m["BottomF"]/60)]] as [String:Any]){_,new in new}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("149-bambu-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder.appendingPathComponent("data"),withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        for (name,value) in [("machine",machine),("process",process),("filament",filament)] {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]).write(to:folder.appendingPathComponent(name+".json"))}
        try writeBox(folder.appendingPathComponent("envelope.stl"),bounds:plan.bounds,height:plan.zMax)
        var args=["--datadir",folder.appendingPathComponent("data").path,"--debug","1","--arrange","0","--outputdir",folder.path,"--curr-bed-type",m.text("BuildPlate"),"--load-settings",folder.appendingPathComponent("machine.json").path+";"+folder.appendingPathComponent("process.json").path,"--load-filaments",folder.appendingPathComponent("filament.json").path,"--export-settings",folder.appendingPathComponent("resolved.json").path,"--slice","0",folder.appendingPathComponent("envelope.stl").path]
        if m.text("PrinterModel")=="H2D" {let left=m.text("H2DNozzle")=="Left";args.insert(contentsOf:["--filament-map",left ? "1":"2","--filament-nozzle-map",left ? "0":"1","--filament-map-mode","Manual"],at:0)}
        do {_=try NativeSliceProcess.run(studio,args,directory:folder)}catch{throw SliceFailure("Bambu Studio 官方启动流程生成失败："+error.localizedDescription)}
        plan.config=try readObject(folder.appendingPathComponent("resolved.json"));let model=try readObject(root.appendingPathComponent("machine/"+p.name+".json"))
        guard let modelID=model["model_id"] as? String else {throw SliceFailure("官方配置缺少机型编号。")};plan.modelID=modelID
        var text=try String(contentsOf:folder.appendingPathComponent("plate_1.gcode"),encoding:.utf8)
        let shape=project.shape,actual=["layer_height":shape[shape.text("SourceMode")=="Triple" ? "TriplePitch":"H"],"initial_layer_print_height":shape["H0"],"line_width":shape["W"],"outer_wall_line_width":shape["W"],"initial_layer_line_width":shape[shape.flag("HasBottom") ? "WB":"W"]]
        for (key,value) in actual {plan.config[key]=G.fmt(value);text=try SliceGcode.replace(text,pattern:"(?m)^; "+key+" = .*$",with:"; "+key+" = "+G.fmt(value))}
        if m.text("PrinterModel")=="H2D" {
            let selected=m.text("H2DNozzle")=="Left" ? "1":"2",nozzle=selected=="1" ? "0":"1"
            guard plan.config["filament_nozzle_map"] as? [String]==[nozzle],plan.config["filament_map"] as? [String]==[selected],SliceGcode.lines(text).contains("; filament_map = "+selected) else {throw SliceFailure("官方喷嘴分配与所选左右喷嘴不一致，已停止导出。")}
        };return text
    }
    static func simpleStart(_ project:NativeSliceProject,official:String) throws -> String {
        let parts=official.components(separatedBy:"; EXECUTABLE_BLOCK_START")
        guard parts.count==2 else {throw SliceFailure("无法识别官方启动边界，已停止简化启动导出。")}
        let regex=try NSRegularExpression(pattern:#"(?m)^T0 H-?\d+\s*$"#)
        guard let hit=regex.firstMatch(in:official,range:NSRange(official.startIndex...,in:official)),let range=Range(hit.range,in:official) else {throw SliceFailure("无法找到官方喷嘴选择指令，已停止导出。")}
        let m=project.machine,heater=m.text("H2DNozzle")=="Left" ? 1:0,tool=official[range].trimmingCharacters(in:.whitespacesAndNewlines)
        return parts[0]+String(format:"\n; EXECUTABLE_BLOCK_START\n; 149 H2D SIMPLE START - selected nozzle must already be loaded\n; No added flushing, dynamic flow calibration or new bed probing\nG21\nG90\nM83\nM220 S100\nM221 S100\nG28\nG1 Z10 F600\nM620 M ; enable the same logical filament remapping as Studio\n%@\nM400\nG90\nM83\nG1 Z10 F600\nG1 X175 Y160 F3000\nM104 S%.5f T%d\nM140 S%.5f\nM109 S%.5f T%d\nM190 S%.5f\nM106 S0\nG92 E0\nM1002 gcode_claim_action : 0\n",tool,m["NT"],heater,m["BT"],m["NT"],heater,m["BT"])
    }
    static func export(_ project:NativeSliceProject,plan:inout Plan,stats:[String:Any],layerCount:Int) throws -> String {
        let m=project.machine,area=Double.pi*1.75*1.75/4,official=try officialGcode(project,plan:&plan)
        guard let startRange=official.range(of:"; MACHINE_START_GCODE_END"),let endRange=official.range(of:"; MACHINE_END_GCODE_START",range:startRange.upperBound..<official.endIndex) else {throw SliceFailure("无法识别官方启动结束边界。")}
        var start=String(official[..<startRange.lowerBound]),end=String(official[endRange.upperBound...])
        let remaining=String(official[startRange.upperBound...]),boundary=try NSRegularExpression(pattern:";(?: CHANGE_LAYER|LAYER_CHANGE)")
        guard let hit=boundary.firstMatch(in:remaining,range:NSRange(remaining.startIndex...,in:remaining)),let range=Range(hit.range,in:remaining) else {throw SliceFailure("无法识别官方首层边界。")}
        var filamentStart=String(remaining[..<range.lowerBound]);guard !filamentStart.contains("; MACHINE_END_GCODE_START") else {throw SliceFailure("无法识别官方首层边界。")}
        filamentStart=SliceGcode.lines(filamentStart).filter{!$0.hasPrefix("M73") && !$0.hasPrefix("M981")}.joined(separator:"\n")
        let simple=m.text("PrinterModel")=="H2D" && m.text("H2DStartup",fallback:"Official")=="Simple"
        if simple {start=try simpleStart(project,official:start);filamentStart=""}
        var lines=SliceGcode.lines(plan.volumeBody)
        for record in try SliceGcode.records(plan.volumeBody).0 {
            guard let e=record.extrusion else {continue};var line=SliceGcode.word(lines[record.line],"E",e/area)
            if !["X","Y","Z"].contains(where:{SliceGcode.scalar(line,$0) != nil}),let f=SliceGcode.scalar(line,"F") {line=SliceGcode.word(line,"F",f/area)};lines[record.line]=line
        }
        lines=lines.filter{!$0.hasPrefix("; GINGER_PELLET_FLOW") && !$0.hasPrefix("; G1_FINISH_CANDIDATE")}.map{$0.hasPrefix("; E_UNITS=") ? "; E_UNITS=FILAMENT_MM":$0}
        end=try SliceGcode.replace(end,pattern:#"(?m)^G1 E-0?\.8 F1800[^\n]*\n"#,with:"; 149: terminal retraction already applied\n",firstOnly:true)
        let stats=SliceParameters(stats)
        for (pattern,value) in [(#"^; model printing time:.*$"#,String(format:"; model printing time: %.0fm; total estimated time: %.0fm",stats["motion_minutes"],stats["motion_minutes"])),(#"^; total layer number:.*$"#,"; total layer number: \(layerCount)"),(#"^; total filament length \[mm\] :.*$"#,String(format:"; total filament length [mm] : %.5f",stats["volume_mm3"]/area)),(#"^; total filament volume \[cm\^3\] :.*$"#,String(format:"; total filament volume [cm^3] : %.5f",stats["volume_mm3"]/1000)),(#"^; total filament weight \[g\] :.*$"#,String(format:"; total filament weight [g] : %.5f",stats["mass_g"])),(#"^; max_z_height:.*$"#,String(format:"; max_z_height: %.5f",plan.zMax))] {start=try SliceGcode.replace(start,pattern:"(?m)"+pattern,with:value)}
        start=try SliceGcode.replace(start,pattern:#"(?m)^M73 [^\n]*\n"#,with:"")
        let body=lines.joined(separator:"\n"),hop=max(simple ? 10:3,project.shape["H0"]+m["BBHop"])
        guard let initial=try SliceGcode.records(body).0.first(where:{$0.after.point != nil})?.after else {throw SliceFailure("路径缺少初始坐标。")}
        let transition=String(format:"\nG90\nG21\nM83\nG92 E0\nG1 Z%.5f F600\nM204 S1000\nG1 X%.5f Y%.5f F%.5f\n",hop,initial.x!,initial.y!,m["BBTravel"]*60)
        var layer=0,out=[String]()
        for line in lines {if line.hasPrefix(";LAYER_CHANGE") {layer+=1;out += ["; CHANGE_LAYER","M73 L\(layer)","M106 S\(layer>1 ? Int((m["BBFan"]*2.55).rounded(.toNearestOrEven)):0)"]};out.append(line)}
        let label=simple ? "simplified H2D startup; official shutdown":"official Bambu Studio startup/shutdown",final=start+"\n; 149 slicer custom paths; "+label+"\n; MACHINE_START_GCODE_END\n"+filamentStart+transition+out.joined(separator:"\n")+"\n; MACHINE_END_GCODE_START\n"+end
        for line in SliceGcode.lines(final) {let code=line.split(separator:";",maxSplits:1,omittingEmptySubsequences:false)[0];guard !code.contains(where:{"{}[]".contains($0)}) else {throw SliceFailure("官方模板存在未展开变量，已停止导出。")};guard !["START_PRINT","END_PRINT","SET_EXTRUDER","SET_PRESSURE_ADVANCE"].contains(where:code.contains) else {throw SliceFailure("拓竹文件不能包含 G1 宏。")}}
        return final
    }
}
