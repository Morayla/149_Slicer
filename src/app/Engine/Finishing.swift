import Foundation
import simd

extension G1Exporter {
    func taper(_ text:String,length:Double,ratio:Double,atStart:Bool=false) throws -> String {
        var lines=G.lines(text)
        let printing=try G.records(text).0.filter{$0.distance>0 && $0.extrusion != nil && !["SKIRT","BRIM","TRAVEL"].contains($0.section)}
        guard !printing.isEmpty else {throw SliceFailure("No extrusion run for taper")}
        var chosen=[G.Record](),total=0.0
        for r in atStart ? printing:Array(printing.reversed()) {
            if let last=chosen.last {
                let left=atStart ? last:r,right=atStart ? r:last
                guard let a=left.after.point,let b=right.before.point else {throw SliceFailure("Invalid taper coordinates")}
                if (0..<3).contains(where:{abs(a[$0]-b[$0])>1e-6}) {break}
            }
            chosen.append(r);total+=r.distance;if total>=length {break}
        }
        if !atStart {chosen.reverse()}
        let used=min(length,total);var distance=0.0
        for r in chosen {
            distance+=r.distance
            let factor=atStart ? ratio+(1-ratio)*min(1,distance/used):1-(1-ratio)*max(0,min(1,(distance-(total-used))/used))
            lines[r.line]=G.word(lines[r.line],"E",r.extrusion!*factor)
        }
        if !atStart && (G.meta(text,"WAVE_Z_MODE") != nil || G.meta(text,"NONPLANAR_MODE") != nil || ["DOUBLE_SCROLL","CRESCENT"].contains(G.meta(text,"SHAPE_KIND") ?? "")),let first=chosen.first,let last=chosen.last {
            lines[first.line]="; GH_TAIL_FINISH_START\n"+lines[first.line];lines[last.line]+="\n; GH_TAIL_FINISH_END"
        }
        return lines.joined(separator:"\n")
    }
    func nonplanarFinish(_ text:String,_ p:SliceParameters) throws -> (String,String) {
        var lines=G.lines(text).filter{!["; GH_RIM_FINISH_START","; GH_RIM_FINISH_END"].contains($0)}
        guard let first=lines.firstIndex(of:"; NONPLANAR_RIM_START"),let last=lines.firstIndex(of:"; NONPLANAR_RIM_END"),let raw=G.meta(text,"NONPLANAR_RIM_REFERENCE_GAPS"),let gaps=try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [Double] else {throw SliceFailure("Invalid nonplanar finish gap count")}
        let records=try G.records(lines.joined(separator:"\n")).0.filter{$0.line>first && $0.line<last && $0.extrusion != nil && $0.distance>0}
        guard !records.isEmpty,records.count==gaps.count else {throw SliceFailure("Invalid nonplanar finish gap count")}
        guard gaps.allSatisfy({$0.isFinite && $0>0 && $0<=p["W"]}) else {throw SliceFailure("Invalid nonplanar finish gap")}
        guard let a=records.first?.before.point,let b=records.last?.after.point,(0..<3).allSatisfy({abs(a[$0]-b[$0])<=0.0001}) else {throw SliceFailure("Nonplanar finish contour must close")}
        let total=records.reduce(0){$0+$1.distance};var distance=0.0
        for (r,h) in zip(records,gaps) {
            distance+=r.distance;let factor=1-(1-p["FinishFlow"])*distance/total
            lines[r.line]=G.word(lines[r.line],"E",r.distance*SliceGeometry.beadArea(p["W"],h)*p["PF"]*p["FM"]*factor)
            guard r.line>0,lines[r.line-1].hasPrefix("; GH_GAP_HEIGHT=") else {throw SliceFailure("Missing nonplanar finish gap metadata")}
            lines[r.line-1]="; GH_GAP_HEIGHT="+G.fmt(h)
        }
        lines[first]+="\n; GH_RIM_FINISH_START";lines[last]="; GH_RIM_FINISH_END\n"+lines[last]
        return (lines.joined(separator:"\n"),"NONPLANAR_RIM")
    }
    func finish(_ text:String,_ candidate:[String:Any]?,_ p:SliceParameters) throws -> (String,String) {
        if G.meta(text,"WARDROBE_BED_TEST")=="1" {return (text,"BED_TEST_NO_EXTRA_RIM")}
        let markers:[(String,[String],String)]=[
            ("TRAVEL_TEST_VASE",["; TRAVEL_TEST_RIMS_DONE=2"],"空移测试件缺少双侧顶部整平。"),
            ("WARDROBE_VASE",["; WARDROBE_RIM_DONE=1"],"挂衣体缺少完整的分件顶部整平。"),
            ("CORNER_PIPE_VASE",["; CORNER_PIPE_RIM_START","; CORNER_PIPE_RIM_END"],"墙角双卷缺少唯一的顶部整平路径。"),
            ("SINGLE_BUD_VASE",["; SINGLE_BUD_RIM_START","; SINGLE_BUD_RIM_END"],"单螺旋花蕾缺少唯一的顶部整平路径。"),
            ("DOUBLE_VASE",["; DOUBLE_VASE_RIM_START","; DOUBLE_VASE_RIM_END"],"双螺旋花瓶缺少唯一的顶部整平路径。")]
        for (key,required,message) in markers where G.meta(text,key)=="1" {
            guard required.allSatisfy({text.components(separatedBy:$0).count==2}) else {throw SliceFailure(message)}
            return (text,"GEOMETRIC_RIM")
        }
        guard p.flag("Finish") else {return (text,"OFF")}
        var mode=p.text("FinishMode")
        if ["auto","loop"].contains(mode),G.meta(text,"NONPLANAR_MODE")=="SADDLE_RIM_V1",G.meta(text,"NONPLANAR_RIM_REFERENCE_GAPS") != nil {return try nonplanarFinish(text,p)}
        if G.meta(text,"NONPLANAR_MODE")=="SOFT_NOISE_Z_V1" && candidate==nil {mode="tail"}
        if mode=="loop" && candidate==nil {throw SliceFailure("Loop finish requires an explicit terminal contour from upstream")}
        if let candidate=candidate,["auto","loop"].contains(mode) {
            guard let raw=candidate["points"] as? [[Double]],(4...10001).contains(raw.count) else {throw SliceFailure("Invalid terminal contour point count")}
            guard raw.allSatisfy({$0.count==3 && $0.allSatisfy(\.isFinite)}) else {throw SliceFailure("Finish contour must contain finite XYZ triples")}
            var points=raw.map{SlicePoint($0[0],$0[1],$0[2])}
            guard let last=try G.records(text).0.last(where:{$0.distance>0 && $0.extrusion != nil}),let origin=last.after.point else {throw SliceFailure("Missing model end")}
            guard (0..<3).allSatisfy({abs(points[0][$0]-origin[$0])<=0.0001 && abs(points.last![$0]-origin[$0])<=0.0001}) else {throw SliceFailure("Terminal contour must start and close at the model end")}
            guard points.allSatisfy({abs($0.z-origin.z)<=0.0001}) else {throw SliceFailure("Loop finish must be level")}
            points[0]=origin;points[points.count-1]=origin
            let height=(candidate["gap"] as? NSNumber)?.doubleValue ?? p["H"]
            guard height.isFinite,height>0,height<=p["W"] else {throw SliceFailure("Invalid finish gap")}
            let lengths=(1..<points.count).map{SliceGeometry.xyLength(points[$0-1],points[$0])}
            guard lengths.allSatisfy({$0>1e-9}) else {throw SliceFailure("Zero-length finish segment")}
            let corrections=(candidate["flow_factors"] as? [Double]) ?? Array(repeating:1,count:lengths.count)
            if candidate["flow_factors"] != nil && candidate["flow_factors"] as? [Double]==nil || corrections.count != lengths.count {throw SliceFailure("Invalid finish flow correction count")}
            guard corrections.allSatisfy({$0.isFinite && $0>0 && $0<=2}) else {throw SliceFailure("Invalid finish flow correction")}
            let total=lengths.reduce(0,+);var distance=0.0
            var lines=["; ===== WALL =====","; GH_FINISH_START: G1 PROCESSOR LEVEL CONTOUR"]
            if p["WallF"]>0 {lines.append("G1 F"+G.fmt(p["WallF"]))}
            for i in lengths.indices {
                let q=points[i+1],length=lengths[i];distance+=length
                let factor=1-(1-p["FinishFlow"])*distance/total,e=length*SliceGeometry.beadArea(p["W"],height)*p["PF"]*p["FM"]*factor*corrections[i]
                lines += ["; GH_GAP_HEIGHT="+G.fmt(height),"G1 X\(G.fmt(q.x)) Y\(G.fmt(q.y)) Z\(G.fmt(q.z)) E\(G.fmt(e))"]
            }
            lines += ["; GH_FINISH_END","; ===== PRINT PATH END ====="]
            return (text+"\n"+lines.joined(separator:"\n"),"LOOP")
        }
        return (try taper(text,length:p["FinishLength"],ratio:p["FinishFlow"]),"TAIL")
    }
    func place(_ text:String,_ p:inout SliceParameters) throws -> String {
        let records=try G.records(text).0,ds=records.filter(\.deposits)
        guard !ds.isEmpty else {throw SliceFailure("No deposited path to place")}
        let xs=ds.compactMap{$0.after.x},ys=ds.compactMap{$0.after.y}
        let sx=try G.metadata(text,"PLACEMENT_CENTER_X",(xs.min()!+xs.max()!)/2),sy=try G.metadata(text,"PLACEMENT_CENTER_Y",(ys.min()!+ys.max()!)/2)
        let cx=try number("CX",G.meta(text,"PATH_SCHEMA") != nil ? 500:sx,0,1000),cy=try number("CY",G.meta(text,"PATH_SCHEMA") != nil ? 500:sy,0,1000)
        let dx=cx-sx,dy=cy-sy;var lines=G.lines(text)
        if abs(dx)+abs(dy)>1e-10 {
            for r in records {
                let code=String(lines[r.line].prefix(while:{$0 != ";"})),ns=String(lines[r.line].prefix(while:{$0 != ";"})) as NSString
                var handled=Set<String>()
                for match in G.words.matches(in:code,range:NSRange(location:0,length:ns.length)) {
                    let axis=ns.substring(with:match.range(at:1))
                    if !["X","Y"].contains(axis) || handled.contains(axis) {continue}
                    handled.insert(axis)
                    let value=Double(ns.substring(with:match.range(at:2)))!
                    lines[r.line]=G.word(lines[r.line],axis,value+(axis=="X" ? dx:dy))
                }
            }
        }
        p["CX"]=cx;p["CY"]=cy
        return G.setMeta(G.setMeta(lines.joined(separator:"\n"),"PLACEMENT_CENTER_X",G.fmt(cx)),"PLACEMENT_CENTER_Y",G.fmt(cy))
    }
}
