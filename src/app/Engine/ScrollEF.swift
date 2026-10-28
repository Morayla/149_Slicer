import Foundation

final class ScrollCompensation {
    let path:[SlicePoint],amount:Double,width:Double,limit:Double,profile:(Double)->Double,metadata:[String]
    var normals:[SlicePoint]
    init(_ path:[SlicePoint],_ p:inout SliceParameters,_ turns:Double) throws {
        self.path=path;amount=p["EF"];width=p["W"];limit=(p["W"]-SliceGeometry.edge*p["H"])/2+p["Tolerance"];normals=Array(repeating:.zero,count:path.count)
        profile=try SliceGeometry.efProfile(&p)
        metadata=["; EF_AMOUNT=\(SliceGeometry.fmt(amount)) EF_FADE_WALL_TURNS=\(Int(p["EFLayers"]))","; EF_TURN_PERCENT="+(p.values["EFTurnPercent"] as! [Double]).map{SliceGeometry.fmt($0)}.joined(separator:",")]
        if amount==0 {return}
        guard turns+1e-9>=p["EFLayers"] else {throw SliceFailure("双螺旋高度不足以完成 EF 补偿圈数；请减少补偿圈数或增加高度。")}
        let gap=p.values["DoubleLaneGap"]==nil ? 9:p["DoubleLaneGap"]
        guard 2*amount<gap else {throw SliceFailure(String(format:"双螺旋 EF 内缩量须小于双线净间隙的一半（当前 %.3f mm）；请减小 EF 或增大双线净间隙。",gap/2))}
        let poly=Array(path.dropLast()),sign=SliceGeometry.area(poly)>0 ? 1.0:-1.0
        var edgeNormals=[SlicePoint]()
        for i in poly.indices {let a=poly[i],b=poly[(i+1)%poly.count],d=SliceGeometry.xyLength(a,b);guard d>=1e-9 else {throw SliceFailure("双螺旋 EF 路径含重合点。")};edgeNormals.append(SlicePoint(sign*(a.y-b.y)/d,sign*(b.x-a.x)/d,0))}
        normals=[]
        for (i,b) in edgeNormals.enumerated() {let a=edgeNormals[(i-1+edgeNormals.count)%edgeNormals.count],den=1+a.x*b.x+a.y*b.y;guard den>=0.1 else {throw SliceFailure("双螺旋转角过急，无法应用 EF。")};normals.append((a+b)/den)}
        normals.append(normals[0])
        let maximum=at(Array(repeating:0,count:path.count))
        for i in 1..<path.count {let d=path[i]-path[i-1],q=maximum[i]-maximum[i-1];guard d.x*q.x+d.y*q.y>0 else {throw SliceFailure("EF 使双螺旋内卷处折叠；请减小内缩量。")}}
        for fraction in [0.25,0.5,0.75,1.0] {try check(poly.indices.map{poly[$0]+fraction*amount*normals[$0]})}
    }
    func at(_ index:Int,time:Double)->SlicePoint {amount==0 ? path[index]:path[index]+amount*profile(time)*normals[index]}
    func at(_ times:[Double])->[SlicePoint] {if amount==0 {return path};return times.enumerated().map{at($0.offset,time:$0.element)}}
    func check(_ poly:[SlicePoint]) throws {do {try SliceGeometry.checkSpacing(poly,width:width)}catch{throw SliceFailure("EF 后双螺旋料道重叠或路径相交；请减小内缩量、减少圈数或增大造型尺寸。")}}
    func checkLap(_ points:[SlicePoint],_ previous:[SlicePoint]?) throws {
        if amount==0 {return}
        if let previous=previous {
            guard zip(points,previous).allSatisfy({SliceGeometry.xyLength($0,$1)<=limit}) else {throw SliceFailure("EF 每圈变化过大，双螺旋层间搭接不足；请增加补偿圈数、平缓逐圈表或减小内缩量。")}
            if zip(points,previous).allSatisfy({$0.x==$1.x && $0.y==$1.y}) {return}
        }
        let closed=points[0].x==points.last!.x && points[0].y==points.last!.y
        try check(closed ? Array(points.dropLast()):points)
    }
}
