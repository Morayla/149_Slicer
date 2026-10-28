import Foundation

extension G1Exporter {
    struct Output {let gcode:String;let body:String;let parameters:SliceParameters;let finish:String;let skirt:String}
    func export(_ input:String) throws -> Output {
        let (cleaned,candidate,_)=try cleanModel(input)
        var p=try configure(cleaned),text=try flowAndSpeed(cleaned,p)
        if p.flag("START_ENABLE") {text=try taper(text,length:p["START_LENGTH"],ratio:p["START_FLOW"],atStart:true)}
        let finished=try finish(text,candidate,p);text=finished.0
        text=try place(text,&p);text=try processTravels(text)
        let skirted=try skirt(text);text=skirted.0
        let endMotion=try genericEnd(text),blocks=try machineBlocks(text,endMotion,p)
        return Output(gcode:try wrapPreview(blocks.0,text,blocks.1,p),body:text,parameters:p,finish:finished.1,skirt:skirted.1)
    }
    func machineBlocks(_ body:String,_ endMotion:String,_ p:SliceParameters) throws -> (String,String) {
        let records=try G.records(body+"\n"+endMotion).0,ds=records.filter{$0.deposits && !["SKIRT","BRIM"].contains($0.section)}
        guard !ds.isEmpty else {throw SliceFailure("Missing printable model bounds")}
        let xs=ds.flatMap{[$0.before.x!,$0.after.x!]},ys=ds.flatMap{[$0.before.y!,$0.after.y!]}
        let x0=xs.min()!-p["MaxW"]/2,x1=xs.max()!+p["MaxW"]/2,y0=ys.min()!-p["MaxW"]/2,y1=ys.max()!+p["MaxW"]/2
        for r in records {
            for axis in ["X","Y","Z"] {if let v=r.after[axis],v<0 || v>1000 {throw SliceFailure("G1 motion outside 1000 mm bed/build range: "+axis)}}
            if r.distance>0 && (r.extrusion ?? 0)>0 {
                let coordinates=[r.before.x!,r.before.y!,r.after.x!,r.after.y!]
                if coordinates.contains(where:{$0<p["MaxW"]/2 || $0>1000-p["MaxW"]/2}) {throw SliceFailure("Printed bead/skirt outside bed; move CX/CY inward")}
            }
        }
        let polygon="[[\(G.fmt(x0)),\(G.fmt(y0))],[\(G.fmt(x1)),\(G.fmt(y0))],[\(G.fmt(x1)),\(G.fmt(y1))],[\(G.fmt(x0)),\(G.fmt(y1))]]"
        let start="""
        ; MACHINE_START_GCODE_START
        EXCLUDE_OBJECT_DEFINE NAME=G1_MODEL CENTER=\(G.fmt((x0+x1)/2)),\(G.fmt((y0+y1)/2)) POLYGON=\(polygon)
        START_PRINT BED_TEMPERATURE=\(G.fmt(p["BT"])) KAMP_LEVELING=1 EXTRUDER_ROTATION_VOLUME=\(G.fmt(p["ROTATION_VOLUME"])) MIXING_STEPPER_ROTATION_VOLUME=\(G.fmt(p["MIXING_VOLUME"])) PURGE_LAYER_HEIGHT=2 PURGE_PARKING_SPEED=10000 PURGE_LENGHT=500 PURGE_SPEED=\(G.fmt(p["PURGE_SPEED"])) PURGE_MATERIAL_QUANTITY=\(G.fmt(p["PURGE_QUANTITY"])) EXTRUDER_TEMPERATURE=\(G.fmt(p["NT"])) EXTRUDER_TEMPERATURE_INITIAL_LAYER=\(G.fmt(p["NT"])) PRESSURE_ADVANCE=\(G.fmt(p["PA"])) PRESSURE_ADVANCE_SMOOTH_TIME=0.5 ZONE_1_TEMPERATURE=\(G.fmt(p["ZONE1"])) ZONE_2_TEMPERATURE=\(G.fmt(p["ZONE2"])) ZONE_3_TEMPERATURE=\(G.fmt(p["ZONE3"]))
        G90
        G21
        M83
        SET_PRESSURE_ADVANCE EXTRUDER=extruder SMOOTH_TIME=0.5
        SET_PRESSURE_ADVANCE ADVANCE=\(G.fmt(p["PA"]))
        SET_EXTRUDER_ROTATION_DISTANCE EXTRUDER=extruder DISTANCE=\(G.fmt(p["ROTATION_VOLUME"]))
        SET_EXTRUDER_ROTATION_DISTANCE EXTRUDER=mixing_stepper DISTANCE=\(G.fmt(p["MIXING_VOLUME"]))
        T0
        M106 S0
        ; MACHINE_START_GCODE_END
        """
        let end="; MACHINE_END_GCODE_START\n"+endMotion+"M106 S0\nM106 P3 S0\nEND_PRINT\nM73 P100 R0\n; MACHINE_END_GCODE_END"
        return (start,end)
    }
    func wrapPreview(_ start:String,_ body:String,_ end:String,_ p:SliceParameters) throws -> String {
        let deposits=try G.records(body).0.filter(\.deposits),byLine=Dictionary(uniqueKeysWithValues:deposits.map{($0.line,$0)})
        let bedTest=G.meta(body,"WARDROBE_BED_TEST")=="1"
        var gap:Double?,oldLayer:String?,count=0,output=[String](),bottomIndex=0,wallTurn:Int?
        let nb=Int(try G.metadata(body,"BOTTOM_LAYERS",0)),bh=try G.metadata(body,"BH",p["H"])
        let base=nb>0 ? p["H0"]+Double(nb-1)*bh:0
        for (i,line) in G.lines(body).enumerated() {
            if line.hasPrefix("; GH_GAP_HEIGHT="),let value=Double(line.dropFirst("; GH_GAP_HEIGHT=".count)) {
                guard value.isFinite else {throw SliceFailure("gap must be finite")};gap=max(0.000001,value)
            }
            if line.hasPrefix("; BOTTOM_LAYER="),let value=Int(line.dropFirst("; BOTTOM_LAYER=".count)) {bottomIndex=value-1}
            if line.hasPrefix("; GH_WALL_TURN="),let value=Int(line.dropFirst("; GH_WALL_TURN=".count)) {wallTurn=value}
            if let r=byLine[i] {
                let z=r.after.z!,key:String,height:Double,name:String
                if r.section=="SKIRT" {key=bedTest ? "model:0":"bottom:0";height=p["H0"];name="Skirt"}
                else if r.section=="BOTTOM" {key="bottom:\(bottomIndex)";height=gap ?? (bottomIndex==0 ? p["H0"]:bh);name="Bottom surface"}
                else {key="model:\(wallTurn ?? max(0,Int(ceil((z-base-0.00002)/p["H"]))-1))";height=gap ?? p["H"];name="Outer wall"}
                if key != oldLayer {count+=1;output += [";LAYER_CHANGE",";Z:"+G.fmt(z)];oldLayer=key}
                let width=r.extrusion!/(r.distance*p["PF"]*height)+height*SliceGeometry.edge
                output += [";HEIGHT:"+G.fmt(height),";WIDTH:"+G.fmt(width),";TYPE:"+name]
            }
            output.append(line)
        }
        let template=try String(contentsOf:resources.appendingPathComponent("G1PreviewConfig.txt"),encoding:.utf8)
        var cfg=[String:String](),keys=[String]()
        for line in G.lines(template) where line.hasPrefix("; ") {
            guard let range=line.range(of:" = ") else {continue}
            let key=String(line[line.index(line.startIndex,offsetBy:2)..<range.lowerBound]),value=String(line[range.upperBound...])
            if cfg[key]==nil {keys.append(key)};cfg[key]=value
        }
        let diameter=String(format:"%.9f",sqrt(4/(Double.pi*p["PF"])))
        cfg["filament_diameter"]=diameter+","+diameter
        cfg["layer_height"]=G.fmt(p["H"]);cfg["initial_layer_print_height"]=G.fmt(p["H0"]);cfg["first_layer_height"]=G.fmt(p["H0"])
        cfg["bottom_shell_layers"]=String(nb);cfg["spiral_mode"]=body.contains("; SPIRAL_JOIN_VERSION=") || body.contains("; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH") ? "1":"0"
        cfg["spiral_finishing_flow_ratio"]=G.fmt(p["FinishFlow"]);cfg["spiral_starting_flow_ratio"]="0"
        if bedTest {cfg["spiral_mode"]=G.meta(body,"WARDROBE_TEST_CONTINUOUS")=="1" ? "1":"0"}
        for key in keys where key.hasSuffix("line_width") || key=="line_width" {cfg[key]=G.fmt(p["W"])}
        for (key,value) in [("extruder_rotation_volume",p["ROTATION_VOLUME"]),("mixing_stepper_rotation_volume",p["MIXING_VOLUME"]),("pressure_advance",p["PA"]),("nozzle_temperature",p["NT"]),("nozzle_temperature_initial_layer",p["NT"]),("hot_plate_temp",p["BT"]),("hot_plate_temp_initial_layer",p["BT"])] {
            if let old=cfg[key] {cfg[key]=old.components(separatedBy:",").map{_ in G.fmt(value)}.joined(separator:",")}
        }
        cfg["machine_start_gcode"]=start.replacingOccurrences(of:"\n",with:"\\n");cfg["machine_end_gcode"]=end.replacingOccurrences(of:"\n",with:"\\n")
        let header="; HEADER_BLOCK_START\n; GingerSlicer compatibility metadata for custom G1 Mini G-code\n; G1_PROCESSOR_FINAL=1\n; Parser compatibility token: generated by GingerSlicer\n; Actual generator: G1 Mini 0.1; migrated custom toolpath, not re-sliced\n; total layer number: \(count)\n; filament_density: \(cfg["filament_density"] ?? "")\n; filament_diameter: \(cfg["filament_diameter"]!)\n; HEADER_BLOCK_END\n; EXECUTABLE_BLOCK_START"
        let footer="; EXECUTABLE_BLOCK_END\n; CONFIG_BLOCK_START\n"+keys.map{"; "+$0+" = "+cfg[$0]!}.joined(separator:"\n")+"\n; CONFIG_BLOCK_END\n"
        return header+"\n"+start+"\n"+output.joined(separator:"\n")+"\n;TYPE:Custom\n"+end+"\n"+footer
    }
}
