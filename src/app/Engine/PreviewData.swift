import Foundation

struct NativePreview {
    struct Layer:Codable {let start:Int,end:Int;let z:Double}
    var segments:[[Double]],ranges:[String:[Double]],volume:Double,length:Double,motionSeconds:Double,layers:[Layer],layerHeights:[Double]
    var beads:[[Double]]
}

extension SliceGeometry {
    static func rounded(_ value:Double,_ places:Int)->Double {Double(fmt(value,places:places))!}
    static func markedBody(_ final:String) throws -> String {
        guard let start=final.range(of:"; MACHINE_START_GCODE_END"),let end=final.range(of:"; MACHINE_END_GCODE_START",range:start.upperBound..<final.endIndex) else {throw SliceFailure("导出路径缺少机器起止标记。")}
        let tail=final[end.upperBound...],stop=tail.range(of:"END_PRINT")?.lowerBound ?? tail.endIndex
        return String(final[start.upperBound..<end.lowerBound])+"\n"+tail[..<stop]
    }
    static func previewData(_ final:String,model:SliceShape) throws -> NativePreview {
        let body=try markedBody(final),records=try SliceGcode.records(body).0,lines=SliceGcode.lines(body)
        var rows=[[Double]](),volume=0.0,length=0.0,seconds=0.0,finishing=false,gap:Double?,starts=[0],pending=false,turn:Int?,tags=[Int?](),recordIndex=0,groupPrinted=false
        rows.reserveCapacity(records.count);tags.reserveCapacity(records.count)
        for (i,line) in lines.enumerated() {
            if line.hasPrefix("; GH_WALL_TURN=") {turn=Int(line.dropFirst("; GH_WALL_TURN=".count))}
            if line.hasPrefix(";LAYER_CHANGE") {pending=true}
            if ["; GH_FINISH_START:","; GH_TAIL_FINISH_START","; GH_RIM_FINISH_START"].contains(where:line.hasPrefix) {finishing=true}
            if ["; GH_FINISH_END","; GH_TAIL_FINISH_END","; GH_RIM_FINISH_END"].contains(where:line.hasPrefix) {finishing=false}
            if line.hasPrefix(";HEIGHT:") {gap=Double(line.dropFirst(";HEIGHT:".count))}else if line.hasPrefix("; GH_GAP_HEIGHT=") {gap=Double(line.dropFirst("; GH_GAP_HEIGHT=".count))}
            guard recordIndex<records.count,records[recordIndex].line==i else {continue}
            let r=records[recordIndex];recordIndex+=1
            guard let a=r.before.point,let b=r.after.point else {continue}
            let d=b-a,d3=sqrt(d.x*d.x+d.y*d.y+d.z*d.z),feed=(r.after.feed ?? 0)/60
            if d3>0 && feed>0 {seconds+=d3/feed};if a==b {continue}
            let printed=r.extrusion != nil && r.extrusion!>=0 && r.distance>0 && ["SKIRT","BOTTOM","WALL"].contains(r.section)
            let role=printed ? (finishing ? 3:r.section=="SKIRT" ? 0:r.section=="BOTTOM" ? 1:2):4,flow=printed && d3>0 ? max(0,r.extrusion ?? 0)*feed/d3:0,height=printed ? (gap ?? .nan):0
            guard !printed || height.isFinite && height>0 else {throw SliceFailure("导出路径缺少有效层高，无法生成层高预览。")}
            if pending && printed {if !rows.isEmpty && groupPrinted {starts.append(rows.count);groupPrinted=false};pending=false}
            rows.append([rounded(a.x,5),rounded(a.y,5),rounded(a.z,5),rounded(b.x,5),rounded(b.y,5),rounded(b.z,5),Double(role),rounded(flow,6),rounded(height,6),rounded(feed,6)]);tags.append(turn)
            if printed {groupPrinted=true;if r.extrusion!>0 {volume+=r.extrusion!;length+=r.distance}}
        }
        func extent(_ column:Int,printing:Bool)->[Double] {var lo=Double.infinity,hi = -Double.infinity;for row in rows where !printing || row[6] != 4 {lo=min(lo,row[column]);hi=max(hi,row[column])};return lo.isFinite ? [lo,hi]:[0,0]}
        var ranges=["flow":extent(7,printing:true),"height":extent(8,printing:true),"print_speed":extent(9,printing:true),"all_speed":extent(9,printing:false)]
        var layers=[NativePreview.Layer]()
        for i in starts.indices {let a=starts[i],b=i+1<starts.count ? starts[i+1]:rows.count;if b>a {layers.append(.init(start:a,end:b,z:rows[a..<b].map{$0[5]}.max()!))}}
        let heights=try displayLayerHeights(rows,tags:tags,model:model),positive=heights.filter{$0>0};ranges["layer_height"]=[positive.min() ?? 0,positive.max() ?? 0]
        let beads=rows.map {s -> [Double] in
            let h=s[8],d=hypot(s[3]-s[0],s[4]-s[1]);if s[6]==4 || s[7]<=0 || h<=0 || d<=0 || s[9]<=0 {return [0,0]}
            let dz=s[5]-s[2],area=s[7]/s[9]*sqrt(d*d+dz*dz)/d,width=area>=Double.pi*h*h/4 ? area/h+h*edge:4*area/(Double.pi*h)
            return [rounded(width,6),h]
        }
        return NativePreview(segments:rows,ranges:ranges,volume:volume,length:length,motionSeconds:seconds,layers:layers,layerHeights:heights,beads:beads)
    }
    static func displayLayerHeights(_ rows:[[Double]],tags:[Int?],model:SliceShape) throws -> [Double] {
        let p=model.parameters,first=p["H0"],bottom=p["BH"]
        let wall=try (model.details["mesh"] as? [String:Any])?["pitch"] as? Double ?? SliceGcode.metadata(model.gcode,"H",p["H"])
        let planar=p.text("SourceMode")=="Crescent" || p.text("SourceMode")=="DoubleScroll" && p["DoubleLines"] != 3
        var heights=rows.map {r -> Double in
            if r[6]==4 {return 0};if r[6]==0 || abs(r[2]-first)<2e-5 && abs(r[5]-first)<2e-5 {return first};if r[6]==1 {return bottom};return planar && r[6]==2 ? r[8]:wall
        }
        if model.details["wardrobe"] != nil {
            var groups=[Int:[Int]](),order=[Int](),previous=wall
            for i in rows.indices {if let turn=tags[i],[2.0,3.0].contains(rows[i][6]) {if groups[turn]==nil {order.append(turn)};groups[turn,default:[]].append(i)}}
            for turn in order {
                let indices=groups[turn]!,group=indices.map{rows[$0]};var height:Double
                if group.allSatisfy({abs($0[2]-first)<2e-5 && abs($0[5]-first)<2e-5}) {height=first}
                else if group.allSatisfy({$0[6]==3}) {height=previous}
                else {
                    let rise=group.last![5]-group.first![2],gaps=group.map{$0[8]}
                    height=rise>2e-5 ? rise:(gaps.max()!-gaps.min()!<2e-5 ? gaps[0]:previous)
                    if abs(height-wall)<2e-5 {height=wall};previous=height
                }
                for i in indices {heights[i]=height}
            }
        }
        guard zip(rows,heights).allSatisfy({row,h in h.isFinite && h>=0 && (row[6]==4 || h>0)}) else {throw SliceFailure("打印层高显示数据无效。")}
        return heights.map{rounded($0,5)}
    }
    static func modelDimensions(_ preview:NativePreview)->[Double] {
        var low=SlicePoint(repeating:.infinity),high=SlicePoint(repeating:-.infinity)
        for (q,bead) in zip(preview.segments,preview.beads) {
            let w=bead[0],h=bead[1];if ![1.0,2.0,3.0].contains(q[6]) || w<=0 || h<=0 {continue}
            for axis in 0..<2 {low[axis]=min(low[axis],q[axis]-w/2,q[axis+3]-w/2);high[axis]=max(high[axis],q[axis]+w/2,q[axis+3]+w/2)}
            low.z=min(low.z,q[2]-h,q[5]-h);high.z=max(high.z,q[2],q[5])
        }
        return low.x.isFinite ? (0..<3).map{rounded(high[$0]-low[$0],2)}:[0,0,0]
    }
    static func materialStats(_ rows:[[Double]],volume:Double,material:SliceParameters) throws -> [String:Double] {
        let density=material["Density"],extra=material["ExtraWasteG"]
        guard density.isFinite,(0.01...30).contains(density) else {throw SliceFailure("材料密度请输入 0.01–30 g/cm³。")}
        guard extra.isFinite,extra>=0 else {throw SliceFailure("额外耗料必须是非负克数。")}
        var skirt=0.0;for s in rows where s[6]==0 && s[9]>0 {skirt+=s[7]*distance3(SlicePoint(s[0],s[1],s[2]),SlicePoint(s[3],s[4],s[5]))/s[9]}
        return ["density_g_cm3":density,"model_mass_g":rounded(max(0,volume-skirt)*density/1000,2),"skirt_mass_g":rounded(skirt*density/1000,2),"extra_mass_g":extra,"mass_g":rounded(volume*density/1000+extra,2)]
    }
}
