import Foundation
import simd

final class G1Exporter {
    typealias G=SliceGcode
    let input:SliceParameters
    let resources:URL
    var resolved=[String:Any]()
    init(settings:SliceParameters,resources:URL) {input=settings;self.resources=resources}
    func number(_ name:String,_ fallback:Double,_ minimum:Double?=nil,_ maximum:Double?=nil) throws -> Double {
        let raw=resolved[name] ?? input.values[name]
        let value:Double
        if raw==nil || (raw as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)=="" {value=fallback}
        else if let v=(raw as? NSNumber)?.doubleValue ?? Double(raw as? String ?? "") {value=v}
        else {throw SliceFailure(name+" must be numeric")}
        guard value.isFinite else {throw SliceFailure(name+" must be finite")}
        if let low=minimum,value<low {throw SliceFailure(name+" is below the minimum")}
        if let high=maximum,value>high {throw SliceFailure(name+" exceeds the maximum")}
        return value
    }
    func flag(_ name:String,_ fallback:Bool)->Bool {
        let raw=resolved[name] ?? input.values[name]
        guard let raw=raw else{return fallback}
        return SliceParameters([name:raw]).flag(name)
    }
    func cleanModel(_ input:String) throws -> (String,[String:Any]?,Bool) {
        var text=input
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw SliceFailure("G is empty")}
        if text.contains("; G1_PROCESSOR_FINAL=1") || text.contains("; EXECUTABLE_BLOCK_START") {throw SliceFailure("Input must be the upstream model body, not a finished printer file")}
        if let start=text.range(of:"; ===== GH CUSTOM START ====="),let end=text.range(of:"; ===== PRINT START ====="),end.lowerBound>start.lowerBound {
            let before=String(text[..<start.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines)
            text=(before.isEmpty ? "":before+"\n\n")+String(text[end.lowerBound...]).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        for marker in ["; MACHINE_END_GCODE_START","; ===== GH CUSTOM END ====="] {if let range=text.range(of:marker) {text=String(text[..<range.lowerBound])}}
        guard text.contains("; ===== PRINT START =====") else {throw SliceFailure("Missing PRINT START marker")}
        var candidate:[String:Any]?
        if let raw=G.meta(text,"G1_FINISH_CANDIDATE") {
            guard let value=try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else {throw SliceFailure("Invalid terminal contour")}
            candidate=value
        }
        if text.contains("; GH_FINISH_START:") {
            let lines=G.lines(text),records=try G.records(text).0
            guard let first=lines.firstIndex(where:{$0.hasPrefix("; GH_FINISH_START:")}),let last=lines.firstIndex(where:{$0.hasPrefix("; GH_FINISH_END")}) else {throw SliceFailure("Unterminated upstream finish block")}
            let ring=records.filter{$0.line>first && $0.line<last && $0.distance>0}
            guard let origin=ring.first?.before.point else {throw SliceFailure("Empty upstream finish block")}
            candidate=["points":SliceGeometry.coordinates([origin]+ring.compactMap{$0.after.point})]
            text=(Array(lines[..<first])+Array(lines[(last+1)...])).joined(separator:"\n")
        }
        for line in G.lines(text) {
            let code=G.command(line)
            guard let cmd=code.split(whereSeparator:{$0.isWhitespace}).first else {continue}
            guard ["G0","G00","G1","G01","G90","G21","M83","G92"].contains(String(cmd)) else {throw SliceFailure("Unsupported model-body command "+cmd)}
            if cmd=="G92" && code != "G92 E0" {throw SliceFailure("Only G92 E0 is supported in model body")}
        }
        let records=try G.records(text).0,deposits=records.filter(\.deposits)
        guard !deposits.isEmpty else {throw SliceFailure("No material-depositing XY path in G")}
        for r in records {
            if let e=r.extrusion {
                if !e.isFinite {throw SliceFailure("E must be finite")}
                if e<0 || r.distance<=0 && e>0 {throw SliceFailure("Supply model paths without E-only prime/retraction; G1 owns these operations")}
            }
        }
        let applied=G.meta(text,"OUTER_FIX_APPLIED")=="1" || G.meta(text,"OUTER_SHAPE_MODE") != nil
        let kind=G.meta(text,"BOTTOM_PATTERN"),count=try G.metadata(text,"BOTTOM_LAYERS",0)
        let hasBottom=deposits.contains{$0.section=="BOTTOM"},legacy=G.meta(text,"PATH_SCHEMA")==nil
        if let declared=G.meta(text,"HAS_BOTTOM"),(declared=="1") != hasBottom {throw SliceFailure("HAS_BOTTOM metadata disagrees with deposited path roles")}
        if applied && !(hasBottom && count==1 && (kind=="SPIRAL" || legacy && text.contains("; SPIRAL_JOIN_VERSION=2"))) {throw SliceFailure("Outer correction requires an explicitly supported single spiral bottom")}
        return (text,candidate,legacy)
    }
    func configure(_ text:String) throws -> SliceParameters {
        let oldPF=try G.metadata(text,"GINGER_PELLET_FLOW_COEFFICIENT",1),oldFM=try G.metadata(text,"COMBINED_FLOW_MULTIPLIER",1),oldF0=try G.metadata(text,"FIRST_LAYER_FLOW_MULTIPLIER",1)
        guard min(oldPF,oldFM,oldF0)>0 else {throw SliceFailure("Input flow multipliers must be positive")}
        let w=try G.metadata(text,"W",0),h=try G.metadata(text,"H",0),h0=try G.metadata(text,"H0",h)
        guard h>0,h<=w,h0>0,h0<=w else {throw SliceFailure("Upstream W,H,H0 metadata is required and must describe valid bead geometry")}
        for (key,value) in [("W",w),("H",h)] {
            if input.values[key] != nil,abs(try number(key,value)-value)>1e-6 {throw SliceFailure(key+" belongs to the geometry generator; remove conflicting downstream input")}
            resolved[key]=value
        }
        var p=SliceParameters(["W":w,"H":h,"H0":h0,"oldpf":oldPF,"oldfm":oldFM,"oldf0":oldF0])
        p["FirstW"]=try G.metadata(text,"FIRST_PATH_WIDTH",w);p["MaxW"]=max(w,try G.metadata(text,"BOTTOM_LINE_WIDTH",w))
        for (key,value) in [("PF",oldPF),("FM",oldFM),("F0",oldF0)] {p[key]=try number(key,value,0.000001)}
        p["F"]=try number("F",0,0);p["BottomF"]=try number("BottomF",p["F"],0);p["WallF"]=try number("WallF",p["F"],0)
        p.values["Finish"]=flag("Finish",true);p["FinishFlow"]=try number("FinishFlow",0.2,0,1)
        let mode=input.text("FinishMode",fallback:"Auto").trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard ["auto","loop","tail"].contains(mode) else {throw SliceFailure("FinishMode must be Auto, Loop or Tail")}
        p.values["FinishMode"]=mode;p["FinishLength"]=try number("FinishLength",20,0.000001)
        p.values["START_ENABLE"]=flag("START_ENABLE",false);p["START_FLOW"]=try number("START_FLOW",1,0.000001,1);p["START_LENGTH"]=try number("START_LENGTH",20,0.000001)
        let fields:[(String,Double,Double)]=[("NT",220,1),("BT",45,0),("PA",0.3,0),("ROTATION_VOLUME",624,0.000001),("MIXING_VOLUME",8000,0.000001),("PURGE_SPEED",500,0.000001),("PURGE_QUANTITY",10000,0),("ZONE1",200,0),("ZONE2",200,0),("ZONE3",200,0)]
        for (key,value,low) in fields {p[key]=try number(key,value,low)}
        return p
    }
    func flowAndSpeed(_ text:String,_ p:SliceParameters) throws -> String {
        let records=try G.records(text).0,byLine=Dictionary(uniqueKeysWithValues:records.map{($0.line,$0)})
        var lines=G.lines(text),currentBottom=0,firstZ:Double?,meshActive=false
        for (i,line) in lines.enumerated() {
            if line=="; MESH_PROCESS_BEGIN" {meshActive=true};if line=="; MESH_PROCESS_END" {meshActive=false}
            if line.hasPrefix("; BOTTOM_LAYER="),let layer=Int(line.dropFirst("; BOTTOM_LAYER=".count)) {currentBottom=layer-1}
            if line.hasPrefix("; GH_GAP_HEIGHT=") {guard let h=Double(line.dropFirst("; GH_GAP_HEIGHT=".count)),h.isFinite else {throw SliceFailure("gap must be finite")}}
            guard let r=byLine[i],let e=r.extrusion,r.distance>0 else {continue}
            if firstZ==nil && e>0 {firstZ=r.after.z}
            let first:Bool
            if r.section=="BOTTOM" {first=currentBottom==0}
            else if let firstZ=firstZ,let before=r.before.z,let after=r.after.z {first=abs(before-firstZ)<1e-6 && abs(after-firstZ)<1e-6 && firstZ<=p["H0"]+1e-6}
            else {first=false}
            let factor=p["PF"]*p["FM"]/(p["oldpf"]*p["oldfm"])*(first ? p["F0"]/p["oldf0"]:1)
            if abs(factor-1)>1e-12 {lines[i]=G.word(lines[i],"E",e*factor)}
            var speed=r.section=="BOTTOM" ? p["BottomF"]:p["WallF"]
            if meshActive,let feed=r.after.feed {speed=speed>0 ? min(speed,feed):feed}
            if speed>0 {lines[i]=G.word(lines[i],"F",speed)}
        }
        var result=lines.joined(separator:"\n")
        for (key,value) in [("GINGER_PELLET_FLOW_COEFFICIENT",p["PF"]),("COMBINED_FLOW_MULTIPLIER",p["FM"]),("FIRST_LAYER_FLOW_MULTIPLIER",p["F0"]),("SKIRT_E_PER_MM",SliceGeometry.beadArea(p["FirstW"],p["H0"])*p["PF"]*p["FM"]*p["F0"])] {result=G.setMeta(result,key,G.fmt(value))}
        return result
    }
}
