import Foundation

enum NativeBambu {
    typealias G=SliceGeometry
    struct Profile {let name:String,bed:[Double],tag:String;var area:[Double]}
    struct Plan {var volumeBody:String,preview:String,bounds:[Double],zMax:Double,profile:Profile,flowReport:[String:Any];var config=[String:Any](),modelID=""}
    static let studio=URL(fileURLWithPath:"/Applications/BambuStudio.app/Contents/MacOS/BambuStudio")
    static func validate(_ project:NativeSliceProject) throws -> Profile {
        let m=project.machine,s=project.shape,model=m.text("PrinterModel")
        var profile:Profile
        switch model {
        case "H2D":profile=Profile(name:"Bambu Lab H2D",bed:[350,320,325],tag:"H2D",area:[0,0,325,320])
        case "P1P":profile=Profile(name:"Bambu Lab P1P",bed:[256,256,256],tag:"P1P",area:[0,0,256,256])
        case "A1":profile=Profile(name:"Bambu Lab A1",bed:[256,256,256],tag:"A1",area:[0,0,256,256])
        case "A1 mini":profile=Profile(name:"Bambu Lab A1 mini",bed:[180,180,180],tag:"A1M",area:[0,0,180,180])
        default:throw SliceFailure("未知拓竹机型。")
        }
        func number(_ key:String,_ lo:Double,_ hi:Double) throws {guard m[key].isFinite,(lo...hi).contains(m[key]) else {throw SliceFailure("\(key) 必须在 \(G.fmt(lo))–\(G.fmt(hi)) 之间。")}}
        try number("Nozzle",0.2,0.8);guard [0.4,0.6,0.8].contains(m["Nozzle"]) else {throw SliceFailure("喷嘴直径支持 0.4 / 0.6 / 0.8 mm。")}
        try number("FilamentDiameter",1.74,1.76);guard m["FilamentDiameter"]==1.75 else {throw SliceFailure("当前拓竹配置使用 1.75 mm 丝材。")}
        for key in ["H","H0","W"]+(s.flag("HasBottom") ? ["BH","WB"]:[])+(s.text("SourceMode")=="Triple" ? ["TriplePitch"]:[]) {guard s[key].isFinite,s[key]>0 else {throw SliceFailure(key+" 必须为正的有限数值。")}}
        for (key,lo,hi) in [("NT",170.0,300.0),("BT",0,model=="A1 mini" ? 80:100),("MaxVolumetric",0.1,35),("BBRetraction",0,3),("BBRetractionSpeed",1,60),("BBHop",0,3),("BBTravel",1,300),("BBFan",0,100),("BottomF",1,18000),("WallF",1,18000),("SKIRT_F",1,18000)] {try number(key,lo,hi)}
        guard ["PLA","PETG","TPU"].contains(m.text("FilamentType")) else {throw SliceFailure("材料类型支持 PLA、PETG、TPU。")}
        guard ["Textured PEI Plate","High Temp Plate"].contains(m.text("BuildPlate")) else {throw SliceFailure("请选择纹理 PEI 或光面高温板。")}
        if model=="H2D" {
            guard ["Left","Right"].contains(m.text("H2DNozzle")) else {throw SliceFailure("H2D 请选择左喷嘴或右喷嘴。")}
            guard ["Official","Simple"].contains(m.text("H2DStartup",fallback:"Official")) else {throw SliceFailure("H2D 启动方式无效。")}
            profile.area=m.text("H2DNozzle")=="Left" ? [0,0,325,320]:[25,0,350,320]
        };return profile
    }
    static func plan(_ model:SliceShape,project:NativeSliceProject,resources:URL) throws -> Plan {
        let profile=try validate(project),m=project.machine,area=Double.pi*1.75*1.75/4
        var mapped=m;mapped.set(["PF":1.0,"G1_RETRACT":m["BBRetraction"]*area,"G1_RETRACT_F":m["BBRetractionSpeed"]*60*area,"G1_RESTORE_F":m["BBRetractionSpeed"]*60*area,"G1_RESTART_EXTRA":0,"G1_Z_HOP":m["BBHop"],"G1_TRAVEL_F":m["BBTravel"]*60,"G1_Z_F":600,"G1_WIPE":false,"G1_WIPE_DISTANCE":0,"G1_RETRACT_MIN_TRAVEL":2])
        let full=try G1Exporter(settings:mapped,resources:resources).export(model.gcode).gcode
        var text=try G.markedBody(full),lines=SliceGcode.lines(text),requested=0.0,effective=0.0,limited=0
        for r in try SliceGcode.records(text).0 where r.extrusion != nil && r.extrusion!>=0 && r.distance>0 {
            let delta=r.after.point!-r.before.point!,d3=sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z),e=r.extrusion!;var speed=r.after.feed ?? 0
            if e>0 {let demand=e*speed/60/d3;requested=max(requested,demand);if demand>m["MaxVolumetric"]+1e-8 {limited+=1};speed=min(speed,m["MaxVolumetric"]*d3/e*60);effective=max(effective,e*speed/60/d3)}
            lines[r.line]=SliceGcode.word(lines[r.line],"F",speed)
        }
        text=lines.joined(separator:"\n");let records=try SliceGcode.records(text).0;var gap=project.shape["H0"],recordIndex=0,bounds=[1e9,1e9,-1e9,-1e9],zMax=0.0
        for (i,line) in lines.enumerated() {
            if line.hasPrefix("; GH_GAP_HEIGHT=") {gap=Double(line.dropFirst("; GH_GAP_HEIGHT=".count))!}
            if line.hasPrefix(";HEIGHT:") {gap=Double(line.dropFirst(";HEIGHT:".count))!}
            guard recordIndex<records.count,records[recordIndex].line==i else {continue};let r=records[recordIndex];recordIndex+=1
            for (axis,limit) in zip(["X","Y","Z"],profile.bed) {if let value=r.after[axis],value<0 || value>limit {throw SliceFailure("\(m.text("PrinterModel"))：路径或抬升超出 \(axis) 轴行程。")}}
            if let z=r.after.z {zMax=max(zMax,z)}
            guard r.distance>0,let e=r.extrusion,e>0 else {continue}
            let a=e/r.distance,w=a>=Double.pi*gap*gap/4 ? a/gap+gap*G.edge:4*a/(Double.pi*gap)
            for position in [r.before,r.after] {
                let x=position.x!,y=position.y!,area=profile.area
                guard x>=area[0]+w/2,x<=area[2]-w/2,y>=area[1]+w/2,y<=area[3]-w/2 else {throw SliceFailure("\(m.text("PrinterModel"))：模型或裙边超出可打印范围，请减小模型或调整中心位置。")}
                guard m.text("PrinterModel") != "P1P" || !(x-w/2<18 && y-w/2<28) else {throw SliceFailure("P1P：模型或裙边进入左前方 18 × 28 mm 禁区。")}
                bounds=[min(bounds[0],x-w/2),min(bounds[1],y-w/2),max(bounds[2],x+w/2),max(bounds[3],y+w/2)]
            }
        }
        return Plan(volumeBody:text,preview:"; MACHINE_START_GCODE_END\n"+text+"\n; MACHINE_END_GCODE_START\nEND_PRINT\n",bounds:bounds,zMax:zMax,profile:profile,flowReport:["requested_peak":requested,"effective_peak":effective,"limited_segments":limited,"limit":m["MaxVolumetric"]])
    }
}
