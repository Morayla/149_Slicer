import Foundation

extension G1Exporter {
    func skirt(_ text:String) throws -> (String,String) {
        let existing=try NSRegularExpression(pattern:#"(?im)^\s*;\s*(?:=====\s*SKIRT\b|TYPE\s*:\s*Skirt\b)"#)
        if existing.firstMatch(in:text,range:NSRange(location:0,length:(text as NSString).length)) != nil {return (text,"EXISTING (preserved)")}
        if !flag("SKIRT_AUTO",true) {return (text,"ABSENT (SKIRT_AUTO=False)")}
        let deposits=try G.records(text).0.filter(\.deposits)
        guard let first=deposits.first,let origin=first.before.point,let firstEnd=first.after.point else {throw SliceFailure("Cannot generate skirt without deposited XY paths")}
        let entryRamp=text.contains("; INNER_ENTRY_Z_RAMP=1"),originZ=origin.z
        var z=firstEnd.z,rate=0.0
        if entryRamp {
            z=try G.metadata(text,"H0",-1);let declared=try G.metadata(text,"INNER_START_H",-1)
            guard min(z,originZ,declared)>0,abs(originZ-declared)<=0.00001,originZ<=firstEnd.z,firstEnd.z<=z+0.00001 else {throw SliceFailure("Invalid layer-height-linked inner entry metadata")}
        } else {
            guard z>0,abs(originZ-z)<=0.001 else {throw SliceFailure("Skirt requires a planar first layer or explicit INNER_ENTRY_Z_RAMP")}
            let layer=deposits.filter{abs($0.after.z!-z)<=0.001 && abs($0.before.z!-z)<=0.001}
            rate=layer.reduce(0){$0+$1.extrusion!}/layer.reduce(0){$0+$1.distance}
        }
        if text.contains("; SPIRAL_JOIN_VERSION=") || entryRamp || G.meta(text,"TRAVEL_TEST_VASE")=="1" {
            rate=try G.metadata(text,"SKIRT_E_PER_MM",-1)
            guard rate>0,rate.isFinite else {throw SliceFailure("Spiral body requires positive SKIRT_E_PER_MM metadata")}
        }
        if G.meta(text,"EDGE_CALIBRATION")=="MEASURED_20260912" {
            let baseline=try G.metadata(text,"EDGE_BASE_SKIRT_E_PER_MM",-1),reference=try G.metadata(text,"EDGE_BASE_SKIRT_FLOW",1)
            guard baseline.isFinite,baseline>0 else {throw SliceFailure("Missing uncalibrated skirt-rate metadata")}
            guard reference.isFinite,reference>0 else {throw SliceFailure("Invalid skirt baseline multiplier")}
            rate=baseline/reference
            for key in ["GINGER_PELLET_FLOW_COEFFICIENT","COMBINED_FLOW_MULTIPLIER","FIRST_LAYER_FLOW_MULTIPLIER"] {rate *= try G.metadata(text,key,1)}
        }
        let hull=G.hull(deposits.flatMap{[$0.before.point!,$0.after.point!]})
        guard hull.count>=3 else {throw SliceFailure("Cannot generate skirt from a degenerate footprint")}
        let width=try number("W",9,0.00001),offset=(try number("SKIRT_GAP",10,0))+width
        var path=[SlicePoint]()
        for i in hull.indices {
            let p=hull[i],previous=hull[(i+hull.count-1)%hull.count],next=hull[(i+1)%hull.count]
            let angle0=atan2(p.y-previous.y,p.x-previous.x)-Double.pi/2,angle1=atan2(next.y-p.y,next.x-p.x)-Double.pi/2
            let turn=SliceGeometry.modulo(angle1-angle0,SliceGeometry.tau),steps=max(1,Int(ceil(turn/(Double.pi/36))))
            for j in 0...steps {let angle=angle0+turn*Double(j)/Double(steps);path.append(SlicePoint(p.x+offset*cos(angle),p.y+offset*sin(angle),0))}
        }
        let aligned=G.meta(text,"LEFT_ALIGNED")=="1"
        if aligned {
            var hits=[(Double,Int,Double)]()
            for i in path.indices {
                let a=path[i],b=path[(i+1)%path.count]
                if abs(b.y-a.y)<1e-10 {continue}
                let t=(origin.y-a.y)/(b.y-a.y)
                if t>=0 && t<=1 {hits.append((a.x+t*(b.x-a.x),i,t))}
            }
            if let (x,i,t)=hits.min(by:{$0.0==$1.0 ? $0.1<$1.1:$0.0<$1.0}),t>1e-8,t<1-1e-8 {path=[SlicePoint(x,origin.y,0)]+Array(path[(i+1)...])+Array(path[...i])}
        }
        let nearest=path.indices.min {a,b in
            if aligned {let x=abs(path[a].y-origin.y),y=abs(path[b].y-origin.y);return x==y ? path[a].x<path[b].x:x<y}
            return pow(path[a].x-origin.x,2)+pow(path[a].y-origin.y,2)<pow(path[b].x-origin.x,2)+pow(path[b].y-origin.y,2)
        }!
        path=Array(path[nearest...])+Array(path[..<nearest])
        let skirtFeed=try number("SKIRT_F",420,0.00001),retract=try number("G1_RETRACT",30,0),retractFeed=try number("G1_RETRACT_F",9000,0.00001)
        let primeFeed=try number("G1_RESTORE_F",9000,0.00001),travelFeed=try number("G1_TRAVEL_F",3000,0.00001),zFeed=try number("G1_Z_F",600,0.00001),hop=try number("G1_Z_HOP",1,0)
        let extra=try number("G1_RESTART_EXTRA",10,0),wipeDistance=try number("G1_WIPE_DISTANCE",10,0),wipeFeed=try number("G1_WIPE_F",600,0.00001)
        let fraction=try number("G1_RETRACT_BEFORE_WIPE",0,0,100)/100,minTravel=try number("G1_RETRACT_MIN_TRAVEL",5,0)
        guard let restoreFeed=first.before.feed ?? first.after.feed else {throw SliceFailure("Set feedrate before first extrusion")}
        let reverseWipe=flag("G1_WIPE",true) && wipeDistance>0 && retract>0 && fraction<1
        let firstWidth=try number("FirstW",width,0.00001),separation=max(width,firstWidth)+2
        let printed=reverseWipe ? try G.openSkirt(path,separation):path+[path[0]]
        var generated=["; ===== SKIRT =====","; G1_AUTO_SKIRT: convex-envelope path","G1 Z"+G.fmt(z+hop)+" F"+G.fmt(zFeed),
            "G1 X"+G.fmt(path[0].x)+" Y"+G.fmt(path[0].y)+" F"+G.fmt(travelFeed),"G1 Z"+G.fmt(z)+" F"+G.fmt(zFeed),"G1 F"+G.fmt(skirtFeed)]
        var last=path[0]
        for p in printed.dropFirst() {
            let e=SliceGeometry.xyLength(p,last)*rate
            if e>0 {generated.append("G1 X\(G.fmt(p.x)) Y\(G.fmt(p.y)) E\(G.fmt(e))")}
            last=p
        }
        generated.append("; G1_SKIRT_TRANSFER_BEGIN")
        if reverseWipe {generated.append("; G1_SKIRT_OPEN_END_CLEARANCE=2; reverse wipe on printed tail")}
        let usedRetract=SliceGeometry.xyLength(origin,last)>=minTravel ? retract:0,usedExtra=usedRetract>0 ? extra:0
        var wipeLength=0.0,wipeSegments=[(SlicePoint,Double)]()
        if reverseWipe && usedRetract>0 {
            last=printed.last!
            let available=(1..<printed.count).reduce(0.0){$0+SliceGeometry.xyLength(printed[$1-1],printed[$1])}
            var remaining=min(wipeDistance,max(0,available-separation))
            for point in printed.dropLast().reversed() {
                if remaining<=0.000001 {break}
                let length=SliceGeometry.xyLength(point,last)
                if length>0.000001 {
                    let take=min(length,remaining),end=last+(point-last)*take/length
                    wipeSegments.append((end,take));wipeLength+=take;remaining-=take
                    if remaining<=0.000001 {break}
                }
                last=point
            }
        }
        let before=Double(G.fmt(wipeSegments.isEmpty ? usedRetract:usedRetract*fraction))!
        if before>0 {generated.append("G1 E-"+G.fmt(before)+" F"+G.fmt(retractFeed)+" ; retract before wipe")}
        generated += wipeLines(wipeSegments,retract:usedRetract-before,retractFeed:retractFeed,wipeFeed:wipeFeed,comment:" ; wipe and retract")
        generated += ["G1 Z"+G.fmt(z+hop)+" F"+G.fmt(zFeed)+" ; lift after wipe","G1 X"+G.fmt(origin.x)+" Y"+G.fmt(origin.y)+" F"+G.fmt(travelFeed),"G1 Z"+G.fmt(originZ)+" F"+G.fmt(zFeed)+" ; return to model entry Z"]
        if usedRetract>0 {generated.append("G1 E"+G.fmt(usedRetract+usedExtra)+" F"+G.fmt(primeFeed)+" ; restore plus Ginger restart extra")}
        generated += ["G1 F"+G.fmt(restoreFeed),"; G1_SKIRT_TRANSFER_END","; ===== "+first.section+" ====="]
        var lines=G.lines(text)
        if entryRamp {
            guard let gapLine=lines[..<first.line].last(where:{$0.hasPrefix("; GH_GAP_HEIGHT=")}) else {throw SliceFailure("Missing entry gap-height metadata")}
            generated.append(gapLine)
        }
        lines.insert(contentsOf:generated,at:first.line)
        let info="GENERATED "+(reverseWipe ? "open skirt, reverse wipe; ":"closed skirt; ")+"gap=\(G.fmt(offset-width)) mm; retract=\(G.fmt(usedRetract)) restore=\(G.fmt(usedRetract+usedExtra)) E units; wipe=\(G.fmt(wipeLength)) mm; XY=\(G.fmt(travelFeed)) mm/min; Z=\(G.fmt(zFeed)) mm/min; hop=\(G.fmt(hop)) mm"
        return (lines.joined(separator:"\n"),info)
    }
}
