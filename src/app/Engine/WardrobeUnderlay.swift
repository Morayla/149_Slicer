import Foundation

final class SliceUnderlay {
    struct Cell:Hashable {let x:Int;let y:Int}
    let points:[SlicePoint],cell:Double
    var grid=[Cell:[Int]]()
    init(_ points:[SlicePoint],cell:Double=12) {
        self.points=points;self.cell=cell
        for i in 0..<points.count-1 {let a=points[i],b=points[i+1]
            for x in Int(floor(min(a.x,b.x)/cell))-1...Int(floor(max(a.x,b.x)/cell))+1 {for y in Int(floor(min(a.y,b.y)/cell))-1...Int(floor(max(a.y,b.y)/cell))+1 {grid[Cell(x:x,y:y),default:[]].append(i)}}
        }
    }
    func below(_ q:SlicePoint)->(Double,Double) {
        var best=(Double.infinity,0.0)
        for i in grid[Cell(x:Int(floor(q.x/cell)),y:Int(floor(q.y/cell))),default:[]] {
            let a=points[i],b=points[i+1],dx=b.x-a.x,dy=b.y-a.y,u=max(0,min(1,((q.x-a.x)*dx+(q.y-a.y)*dy)/max(1e-12,dx*dx+dy*dy))),d=hypot(q.x-a.x-u*dx,q.y-a.y-u*dy),z=a.z+u*(b.z-a.z)
            if d<best.0-1e-7 || (abs(d-best.0)<1e-7 && z<best.1) {best=(d,z)}
        }
        return best
    }
}

extension SliceGeometry {
    static func underlayHeights(_ previous:[SlicePoint],_ points:[SlicePoint],_ limit:Double) throws -> ([Double],Double) {
        if previous.count==points.count && zip(previous,points).allSatisfy({$0.x==$1.x && $0.y==$1.y}) {
            var heights=[SIMD2<Double>:Double]()
            for q in previous {let key=SIMD2(q.x,q.y);heights[key]=min(q.z,heights[key] ?? q.z)}
            return (points.map{max(0,$0.z-heights[SIMD2($0.x,$0.y)]!)},0)
        }
        let under=SliceUnderlay(previous);var hs=[Double](),support=0.0
        for q in points {let (distance,z)=under.below(q);support=max(support,distance);guard distance<=limit else {throw SliceFailure(String(format:"开孔回转缺少前一圈支撑：横距 %.3f mm。",distance))};hs.append(max(0,q.z-z))}
        return (hs,support)
    }
    static func firstRise(_ u:Double,_ pitch:Double,_ length:Double)->Double {
        if u<=0 {return 0};if u>=1 {return pitch}
        let lead=min(0.6,0.2*pitch),scale=min(20,length/8),early = -expm1(-u*length/scale)/(-expm1(-length/scale))
        return (pitch-lead)*u+lead*early
    }
    static func measuredWardrobeValues(_ p:SliceParameters) throws -> [Double] {
        let post=p.flag("WardEFGrouped") && p["WardLayout"]==2 && [1.0,2.0,3.0,4.0].contains(p["WardPart"]) && !p.flag("WardBedTest")
        let defaults=post ? [0.71,0,0.69,0.65,0.53,0.31,0.21,0.21,0.15]:[1.07,0,0.60,0.60,0.22,0.17,0.17],prefix=post ? "WardPostEFLayer":"WardEFLayer"
        let values=defaults.enumerated().map{i,v in p.values[prefix+String(i+1)]==nil ? v:p[prefix+String(i+1)]}
        guard values.allSatisfy({$0.isFinite && $0>=0}) else {throw SliceFailure("逐层内缩量须为非负有限数值。")};return values
    }
    static func measuredLayerOffset(_ values:[Double],_ index:Double)->Double {
        if index<=0 {return values[0]};if index>=Double(values.count) {return 0}
        let i=Int(index),u=index-Double(i),a=values[i],b=i+1<values.count ? values[i+1]:0
        return a+(b-a)*u*u*(3-2*u)
    }
    static func offsetAtSection(_ sections:WardrobeSliceSections,_ points:[SlicePoint],_ opened:Bool,_ amounts:[Double]) throws -> [SlicePoint] {
        let nodes=Array(sections.nodes.dropLast()),m=nodes.count,base=Array(sections.loop(points[0].z,opened).dropLast()),sign=area(base)>0 ? 1.0:-1.0
        var out=[SlicePoint]()
        for (i,q) in points.enumerated() {
            let amount=amounts[i];if amount==0 {out.append(q);continue}
            let j=i%m,a=sections.at(nodes[(j-1+m)%m],q.z,opened),b=sections.at(nodes[j],q.z,opened),c=sections.at(nodes[(j+1)%m],q.z,opened)
            var normals=[SlicePoint]()
            for (x,y) in [(a,b),(b,c)] {let dx=y.x-x.x,dy=y.y-x.y,d=hypot(dx,dy);guard d>=1e-9 else {throw SliceFailure("逐层 EF 路径含重合点。")};normals.append(SlicePoint(-sign*dy/d,sign*dx/d,0))}
            let n1=normals[0],n2=normals[1],den=1+n1.x*n2.x+n1.y*n2.y
            guard den>=0.1 else {throw SliceFailure("逐层 EF 转角过急。")};out.append(SlicePoint(q.x+amount*(n1.x+n2.x)/den,q.y+amount*(n1.y+n2.y)/den,q.z))
        }
        return out
    }
}
