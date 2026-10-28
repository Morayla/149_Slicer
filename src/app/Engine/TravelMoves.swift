import Foundation
import simd

extension G1Exporter {
    func endFromRuns(_ runs:[G.Record],clearance:Double=0) throws -> String {
        guard let tail=runs.last?.after,let origin=tail.point else {throw SliceFailure("Model must end on a print path")}
        var last=origin
        let retract=try number("G1_RETRACT",30,0),rf=try number("G1_RETRACT_F",9000,0.000001)
        let zf=try number("G1_Z_F",600,0.000001),hop=try number("G1_Z_HOP",1,0),wf=try number("G1_WIPE_F",600,0.000001)
        let distance=flag("G1_WIPE",true) ? try number("G1_WIPE_DISTANCE",10,0):0
        let fraction=try number("G1_RETRACT_BEFORE_WIPE",0,0,100)/100
        var segments=[(SlicePoint,Double)](),remaining=distance
        if retract>0 && fraction<1 {
            for r in runs.reversed() {
                guard let a=r.before.point,let b=r.after.point else {throw SliceFailure("Invalid wipe coordinates")}
                if (0..<3).contains(where:{abs(last[$0]-b[$0])>1e-5}) || abs(a.z-origin.z)>1e-5 {break}
                let take=min(remaining,r.distance)
                if take<=1e-9 {break}
                let q=b+(a-b)*take/r.distance;segments.append((q,take));last=q;remaining-=take
            }
        }
        let before=segments.isEmpty ? retract:retract*fraction
        var lines=["; G1_GENERIC_END_BEGIN","M83"]
        if before>0 {lines.append("G1 E-"+G.fmt(before)+" F"+G.fmt(rf))}
        lines += wipeLines(segments,retract:retract-before,retractFeed:rf,wipeFeed:wf)
        lines += ["G1 Z"+G.fmt(max(origin.z,clearance)+hop)+" F"+G.fmt(zf),"; G1_GENERIC_END_END"]
        return lines.joined(separator:"\n")+"\n"
    }
    func wipeLines(_ segments:[(SlicePoint,Double)],retract:Double,retractFeed:Double,wipeFeed:Double,comment:String="")->[String] {
        guard !segments.isEmpty else{return []}
        let length=segments.reduce(0){$0+$1.1},speed=retract>0 ? min(wipeFeed,retractFeed*length/retract):wipeFeed
        var lines=[";WIPE_START","G1 F"+G.fmt(speed)],assigned=0.0
        for (i,item) in segments.enumerated() {
            let (q,d)=item,amount=i==segments.count-1 ? retract-assigned:Double(G.fmt(retract*d/length))!
            assigned+=amount;lines.append("G1 X\(G.fmt(q.x)) Y\(G.fmt(q.y)) E\(G.fmt(-amount))"+comment)
        }
        lines.append(";WIPE_END");return lines
    }
    func topWipe(_ text:String) throws -> String {
        let lines=G.lines(text)
        guard let start=lines.firstIndex(where:{$0.hasPrefix("; GH_FINISH_START:")}) else {return ""}
        guard let end=lines.firstIndex(where:{$0.hasPrefix("; GH_FINISH_END")}) else {throw SliceFailure("Missing finish end")}
        let ring=try G.records(text).0.filter{$0.line>start && $0.line<end && $0.distance>0 && $0.extrusion != nil}
        guard let origin=ring.first?.before.point,let tail=ring.last?.after.point else {throw SliceFailure("Finish circle has no motion")}
        guard (0..<3).allSatisfy({abs(origin[$0]-tail[$0])<=0.0001}) else {throw SliceFailure("Finish circle must be closed before wiping")}
        guard ring.allSatisfy({abs($0.before.z!-tail.z)<=0.0001 && abs($0.after.z!-tail.z)<=0.0001}) else {throw SliceFailure("Finish circle must be level")}
        let retract=try number("G1_RETRACT",30,0),rf=try number("G1_RETRACT_F",9000,0.00001),wf=try number("G1_WIPE_F",600,0.00001)
        let distance=flag("G1_WIPE",true) ? try number("G1_WIPE_DISTANCE",10,0):0
        let fraction=try number("G1_RETRACT_BEFORE_WIPE",0,0,100)/100,hop=try number("G1_Z_HOP",1,0),zf=try number("G1_Z_F",600,0.00001)
        var result=["; G1_TOP_FINISH_RETRACT_BEGIN","M83"],segments=[(SlicePoint,Double)](),remaining=distance
        if retract>0 && fraction<1 {
            for r in ring {
                let take=min(r.distance,remaining);if take<=0.000001 {break}
                let a=r.before.point!,b=r.after.point!;segments.append((a+(b-a)*take/r.distance,take));remaining-=take
            }
        }
        let before=Double(G.fmt(segments.isEmpty ? retract:retract*fraction))!
        if before>0 {result.append("G1 E-"+G.fmt(before)+" F"+G.fmt(rf))}
        result += wipeLines(segments,retract:retract-before,retractFeed:rf,wipeFeed:wf)
        result += ["G1 Z"+G.fmt(tail.z+hop)+" F"+G.fmt(zf)," ; G1_TOP_FINISH_RETRACT_END"]
        return result.joined(separator:"\n")+"\n"
    }
    func genericEnd(_ text:String) throws -> String {
        if text.contains("; GH_FINISH_START:") {return try topWipe(text)}
        var runs=[G.Record]()
        for r in try G.records(text).0 {
            if r.distance>0,let e=r.extrusion,e>=0 {runs.append(r)}
            else if r.distance>0 {runs.removeAll(keepingCapacity:true)}
        }
        let clearance=G.meta(text,"NONPLANAR_MODE") != nil ? try G.metadata(text,"TOTAL_HEIGHT",0):0
        return try endFromRuns(runs,clearance:clearance)
    }
    func processTravels(_ text:String) throws -> String {
        let records=try G.records(text).0,lines=G.lines(text)
        var replace=[Int:String](),remove=Set<Int>(),i=0,next=Array<G.Record?>(repeating:nil,count:records.count+1)
        if !records.isEmpty {
            for k in stride(from:records.count-1,through:0,by:-1) {let r=records[k];next[k]=r.distance>0 && r.extrusion != nil ? r:next[k+1]}
        }
        var runs=[G.Record](),seenPrint=false
        while i<records.count {
            let r=records[i]
            if !["G0","G00"].contains(r.command) {
                if r.distance>0,let e=r.extrusion {seenPrint=true;if e>=0{runs.append(r)}else{runs.removeAll(keepingCapacity:true)}}
                else if r.distance>0 {runs.removeAll(keepingCapacity:true)}
                i+=1;continue
            }
            var run=[r],j=i+1
            while j<records.count && ["G0","G00"].contains(records[j].command) {run.append(records[j]);j+=1}
            guard seenPrint,let following=next[j] else {if run.contains(where:{$0.distance>0}){runs.removeAll(keepingCapacity:true)};i=j;continue}
            guard let start=run[0].before.point,let end=run.last!.after.point,run.allSatisfy({$0.after.point != nil}) else {throw SliceFailure("Travel endpoints must have XYZ")}
            let retract=run.reduce(0){$0+$1.distance} >= (try number("G1_RETRACT_MIN_TRAVEL",5,0)) ? try number("G1_RETRACT",30,0):0
            let pf=try number("G1_RESTORE_F",9000,0.000001),tf=try number("G1_TRAVEL_F",3000,0.000001),zf=try number("G1_Z_F",600,0.000001),hop=try number("G1_Z_HOP",1,0)
            _=try number("G1_RETRACT_F",9000,0.000001)
            let safe=max(start.z,run.map{$0.after.z!}.max()!)+hop
            var block=["; G1_TRAVEL_BEGIN"]
            if retract>0 {block += G.lines(try endFromRuns(runs)).filter{!$0.hasPrefix("G1 Z") && !$0.contains("G1_GENERIC_END")}}
            block.append("G1 Z"+G.fmt(safe)+" F"+G.fmt(zf))
            for q in run {block.append("G1 X"+G.fmt(q.after.x!)+" Y"+G.fmt(q.after.y!)+" F"+G.fmt(tf))}
            block.append("G1 Z"+G.fmt(end.z)+" F"+G.fmt(zf))
            if retract>0 {block.append("G1 E"+G.fmt(retract+(try number("G1_RESTART_EXTRA",10,0)))+" F"+G.fmt(pf))}
            guard let feed=following.after.feed else {throw SliceFailure("No print feedrate after travel")}
            block += ["G1 F"+G.fmt(feed),"; G1_TRAVEL_END"]
            replace[r.line]=block.joined(separator:"\n");remove.formUnion(run.dropFirst().map(\.line))
            if run.contains(where:{$0.distance>0}) {runs.removeAll(keepingCapacity:true)}
            i=j
        }
        return lines.enumerated().compactMap{remove.contains($0.offset) ? nil:replace[$0.offset] ?? $0.element}.joined(separator:"\n")
    }
}
