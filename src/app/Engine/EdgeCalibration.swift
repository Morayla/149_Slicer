import Foundation

extension SliceGeometry {
    struct EdgeReport {let min:Double;let max:Double;let segments:Int;let baseRate:Double;let flow:Double}
    static func edgeEligible(_ p:SliceParameters)->Bool {
        !p.flag("_FilamentMode") && ["Cylinder","Cone"].contains(p.text("SourceMode")) && p["HasBottom"]==1 && p["B"]==1 && p.text("BottomKind",fallback:"Annular")=="Annular" && p.text("BottomPattern",fallback:"Spiral")=="Spiral" && p.flag("AlignLeft")
    }
    static func radialDelta(_ degrees:Double,inward:Double,outward:Double)->Double {
        let theta=modulo(degrees,360),knots:[(Double,Double)]=[(0,outward),(20,0),(180,0),(270,-inward),(330,0),(360,outward)]
        for i in 1..<knots.count {
            let (a,da)=knots[i-1],(b,db)=knots[i]
            if a<=theta && theta<=b {return da+(db-da)*smooth((theta-a)/(b-a))}
        }
        return 0
    }
    static func displayedWidth(volume:Double,distance:Double,height:Double,multiplier:Double)->Double {
        if volume<=1e-10 || distance<=1e-10 || height<=1e-10 {return 0}
        let area=volume*multiplier/distance
        return area>=Double.pi*height*height/4 ? area/height+height*edge:4*area/(Double.pi*height)
    }
    static func correctEdge(_ points:[SlicePoint],_ volumes:[Double?],_ gaps:[Double],_ n:Int,_ p:SliceParameters) throws -> ([SlicePoint],[Double?],EdgeReport) {
        let inward=p["EdgeBulgeIn"],outward=p["EdgeDipOut"],flow=p.values["_EdgeFirstFlow"]==nil ? 1:p["_EdgeFirstFlow"]
        guard flow.isFinite,flow>0 else {throw SliceFailure("首层外缘校准需要有效的首层流量比例。")}
        guard points.count==volumes.count+1,gaps.count==volumes.count,volumes.count%n==0 else {throw SliceFailure("首层外缘校准需要完整的圆形螺旋采样。")}
        func rounded(_ v:Double,_ places:Int=6)->Double {Double(fmt(v,places:places))!}
        var baseVolume=0.0,baseLength=0.0
        for i in volumes.indices {
            let a=points[i],b=points[i+1]
            let e=volumes[i].map{abs(flow-1)>1e-12 ? rounded(rounded($0)*flow,5):rounded($0)} ?? 0
            if e>0 {
                baseVolume+=e
                baseLength+=hypot(rounded(rounded(a.x),5)-rounded(rounded(b.x),5),rounded(rounded(a.y),5)-rounded(rounded(b.y),5))
            }
        }
        let count=volumes.count
        var lengths=[Double](),edges=[Double](),bins=Array(repeating:[Int](),count:n)
        for i in volumes.indices {
            let a=points[i],b=points[i+1],length=xyLength(a,b)
            lengths.append(length)
            let width=displayedWidth(volume:volumes[i] ?? 0,distance:length,height:gaps[i],multiplier:flow)
            edges.append((hypot(a.x,a.y)+hypot(b.x,b.y))/2+width/2)
            if width>1e-7 {bins[i%n].append(i)}
        }
        var offsets=Array(repeating:0.0,count:count)
        let blend=min(1,p["WB"]/6)
        for candidates in bins where !candidates.isEmpty {
            let outer=candidates.map{edges[$0]}.max()!,first=candidates[0],a=points[first],b=points[first+1]
            let degrees=modulo(atan2(a.y+b.y,a.x+b.x)*180/Double.pi,360)
            let delta=radialDelta(degrees,inward:inward,outward:outward)
            for i in candidates {
                let below=max(0,outer-edges[i]),t=min(1,below/blend)
                var shift=delta*(1-smooth(t))
                if delta<0 {shift=min(shift,min(0,outer+delta-edges[i]))}
                offsets[i]=shift
            }
        }
        var changed=[SlicePoint](),shifts=[Double]()
        for (i,q) in points.enumerated() {
            let shift=i==0 || i==count ? 0:(offsets[i-1]+offsets[i])/2,r=hypot(q.x,q.y)
            if abs(shift)<1e-10 {changed.append(q);shifts.append(0);continue}
            guard r+shift>p["Din"]/2+p["WB"]/2 else {throw SliceFailure("首层外缘校准量过大，已侵入内部填充区域。")}
            changed.append(SlicePoint(q.x*(r+shift)/r,q.y*(r+shift)/r,q.z));shifts.append(shift)
        }
        var result=[Double?]()
        for (i,value) in volumes.enumerated() {
            guard let e=value else {result.append(nil);continue}
            if changed[i]==points[i] && changed[i+1]==points[i+1] {result.append(e);continue}
            guard lengths[i]>1e-10 else {throw SliceFailure("外缘校准遇到零长度打印段。")}
            result.append(e*xyLength(changed[i],changed[i+1])/lengths[i])
        }
        guard baseLength>0 else {throw SliceFailure("首层外缘校准没有有效挤出路径。")}
        return (changed,result,EdgeReport(min:shifts.min() ?? 0,max:shifts.max() ?? 0,segments:offsets.filter{abs($0)>1e-9}.count,baseRate:baseVolume/baseLength,flow:flow))
    }
}
