import Foundation

extension SliceGeometry {
    struct HelicalResult {
        let wall:[SlicePoint],laps:[[SlicePoint]],turns:Int,pitch:Double,maxShift:Double,maxSegment:Double
    }
    static func pathFractions(_ path:[SlicePoint])->[Double] {
        let lengths=(1..<path.count).map{xyLength(path[$0-1],path[$0])},perimeter=lengths.reduce(0,+)
        var result=[0.0];for distance in lengths {result.append(result.last!+distance/perimeter)};result[result.count-1]=1;return result
    }
    static func helicalHeader(_ p:SliceParameters,kind:String,pitch:Double,start:SlicePoint,metadata:[String]=[],bottomHeight:Double?=nil)->[String] {
        ["; PATH_SCHEMA=G1_GEOMETRY_V1","; SHAPE_KIND="+kind]+metadata+[
            "; HAS_BOTTOM=0","; BOTTOM_LAYERS=0","; BOTTOM_PATTERN=NONE","; OUTER_FIX_ELIGIBLE=0","; OUTER_FIX_APPLIED=0","; EF_AMOUNT=0","; EF_FADE_WALL_TURNS=0","; E_UNITS=VOLUME_MM3","; GINGER_PELLET_FLOW_COEFFICIENT=1","; COMBINED_FLOW_MULTIPLIER=1","; FIRST_LAYER_FLOW_MULTIPLIER=1","; H=\(fmt(pitch)) W=\(fmt(p["W"]))","; H0=\(fmt(p["H0"])) BH=\(fmt(bottomHeight ?? p["H"]))","; FIRST_PATH_WIDTH="+fmt(p["W"]),"; BOTTOM_LINE_WIDTH="+fmt(p["W"]),"; TOTAL_HEIGHT="+fmt(p["CH"]),"; PLACEMENT_CENTER_X=0 PLACEMENT_CENTER_Y=0","; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH","; ===== PRINT START =====","G90","G21","M83","G92 E0","G0 Z"+fmt(p["H0"])+" F600","G0 X\(fmt(start.x)) Y\(fmt(start.y)) F3000","; ===== WALL ====="]
    }
    static func helicalPath(_ p:SliceParameters,fractions:[Double],marker:String?,lines:inout [String],captureLaps:Bool=false,at:(Int,Double)->SlicePoint,validate:(([SlicePoint],[SlicePoint]?) throws -> Void)?=nil) throws -> HelicalResult {
        let first=p["H0"],height=p["CH"],nominal=p["H"],width=p["W"],turns=max(1,Int(ceil((height-first)/nominal-1e-9))),pitch=(height-first)/Double(turns)
        var wall=[SlicePoint](),laps=[[SlicePoint]](),previous:[SlicePoint]?,maxShift=0.0,maxSegment=0.0
        wall.reserveCapacity((fractions.count-1)*(turns+2)+1)
        func emit(_ zs:[Double],_ hs:[Double],_ turn:Int) throws {
            try SliceComputation.check()
            let points=zs.enumerated().map{at($0.offset,$0.element)}
            try validate?(points,previous)
            if let previous=previous {maxShift=max(maxShift,zip(previous,points).map{xyLength($0,$1)}.max() ?? 0)}
            lines.append("; GH_WALL_TURN=\(turn)")
            for i in 0..<points.count-1 {
                let q=points[i+1],lo=hs[i],hi=hs[i+1],gap=(lo+hi)/2,length=xyLength(points[i],q),area=width*gap-edge*(lo*lo+lo*hi+hi*hi)/3,e=length*area
                guard e.isFinite,e>0 else {throw SliceFailure("连续上升路径含无效挤出量。")}
                maxSegment=max(maxSegment,length)
                lines += ["; GH_GAP_HEIGHT="+fmt(gap),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(e)) F420"]
            }
            wall += wall.isEmpty ? points:Array(points.dropFirst());previous=points;if captureLaps {laps.append(points)}
        }
        try emit(Array(repeating:first,count:fractions.count),Array(repeating:first,count:fractions.count),0)
        if let marker=marker {lines.append("; "+marker+"_RISE_START")}
        for turn in 0..<turns {
            var zs=fractions.map{first+pitch*(Double(turn)+$0)};if turn==turns-1 {zs[zs.count-1]=height}
            try emit(zs,turn==0 ? fractions.map{pitch*$0}:Array(repeating:pitch,count:fractions.count),turn+1)
        }
        if let marker=marker {lines += ["; "+marker+"_RISE_END","; "+marker+"_RIM_START"]};lines.append("; GH_RIM_FINISH_START")
        try emit(Array(repeating:height,count:fractions.count),fractions.map{pitch*(1-$0)},turns+1)
        lines.append("; GH_RIM_FINISH_END");if let marker=marker {lines.append("; "+marker+"_RIM_END")};lines.append("; ===== PRINT PATH END =====")
        return HelicalResult(wall:wall,laps:laps,turns:turns,pitch:pitch,maxShift:maxShift,maxSegment:maxSegment)
    }
    static func readProfile(_ resources:URL,_ name:String) throws -> [String:Any] {
        let url=resources.appendingPathComponent(name+".json")
        guard let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any] else {throw SliceFailure("Invalid profile: "+name)}
        return object
    }
    static func alignedLoop(_ input:[SlicePoint],_ aligned:Bool)->[SlicePoint] {
        var poly=input
        if aligned {let index=poly.indices.min{poly[$0].x==poly[$1].x ? poly[$0].y<poly[$1].y:poly[$0].x<poly[$1].x}!;poly=Array(poly[index...])+poly[..<index]}
        return poly+[poly[0]]
    }
    static func simplify(_ points:[SlicePoint],tolerance:Double=0.01)->[SlicePoint] {
        var keep:Set<Int>=[0,points.count-1],stack=[(0,points.count-1)]
        while let (lo,hi)=stack.popLast() {
            if hi-lo<2 {continue};var distance = -Double.infinity,index=lo+1
            for k in lo+1..<hi {let d=pointDistance(points[k],points[lo],points[hi]);if d>=distance {distance=d;index=k}}
            if distance>tolerance {keep.insert(index);stack += [(lo,index),(index,hi)]}
        }
        return keep.sorted().map{points[$0]}
    }
}
