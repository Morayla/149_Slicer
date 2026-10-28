import Foundation

extension SliceGeometry {
    struct Polyline {
        let points:[SlicePoint]
        let cumulative:[Double]
        let length:Double
        init(_ points:[SlicePoint]) {
            self.points=points;var cumulative=[0.0]
            for i in 1..<points.count {cumulative.append(cumulative.last!+xyLength(points[i-1],points[i]))}
            self.cumulative=cumulative;length=cumulative.last!
        }
        func at(_ fraction:Double,z:Double=0)->SlicePoint {
            let distance=modulo(fraction,1)*length,index=min(points.count-2,max(0,upperBound(cumulative,distance)-1))
            let u=(distance-cumulative[index])/(cumulative[index+1]-cumulative[index])
            var q=points[index]+u*(points[index+1]-points[index]);q.z=z;return q
        }
    }
    struct TripleOutline {
        let points:[SlicePoint],centers:[SlicePoint],joins:[SlicePoint]
        let gap:Double,lobeDiameter:Double,centerDistance:Double,actualDiameter:Double
    }
    static func tripleOutline(diameter:Double,turns:Double,samples:Int=250,rotation:Double=0) throws -> TripleOutline {
        guard diameter.isFinite,diameter>0 else {throw SliceFailure("三螺旋路径外接直径必须大于 0。")}
        guard turns.isFinite,turns>1/3.0,turns<=20 else {throw SliceFailure("长螺旋圈数必须大于 1/3 且不超过 20。")}
        guard (50...1000).contains(samples) else {throw SliceFailure("每转采样数必须是 50–1000 的整数。")}
        guard rotation.isFinite else {throw SliceFailure("旋转角度必须为有限数值。")}
        let rotation=modulo(rotation,360)*Double.pi/180
        func build(_ gap:Double,_ n:Int)->([SlicePoint],[SlicePoint],[[SlicePoint]],[[SlicePoint]],Double,Double) {
            let c=gap/Double.pi,tl=turns*tau,ts=(turns-1/3.0)*tau,rl=c*tl,rs=c*ts,separation=rl+rs,triHeight=separation*sqrt(3)/2
            let ca=cos(rotation),sa=sin(rotation)
            let centers=[SlicePoint(-separation/2,-triHeight/3,0),SlicePoint(separation/2,-triHeight/3,0),SlicePoint(0,2*triHeight/3,0)].map{SlicePoint($0.x*ca-$0.y*sa,$0.x*sa+$0.y*ca,0)}
            var longs=[[SlicePoint]](),shorts=[[SlicePoint]](),joins=[SlicePoint]()
            for (k,center) in centers.enumerated() {
                let phase=rotation+Double(k)*tau/3-tl
                func branch(_ theta:Double,_ phase:Double)->[SlicePoint] {
                    let count=max(20,Int(ceil(Double(n)*theta/tau))+1)
                    return (0..<count).map {i in let t=theta*Double(i)/Double(count-1),r=c*t,a=t+phase;return SlicePoint(center.x+r*cos(a),center.y+r*sin(a),0)}
                }
                longs.append(branch(tl,phase));shorts.append(branch(ts,phase+Double.pi))
            }
            for (k,center) in centers.enumerated() {
                let angle=rotation+Double(k)*tau/3,point=SlicePoint(center.x+rl*cos(angle),center.y+rl*sin(angle),0)
                longs[k][longs[k].count-1]=point;shorts[(k+1)%3][shorts[(k+1)%3].count-1]=point;joins.append(point)
            }
            return (centers,joins,longs,shorts,rl,separation)
        }
        let unit=build(1,max(1000,samples)),radius=(unit.2+unit.3).flatMap{$0}.map{hypot($0.x,$0.y)}.max()!,gap=diameter/(2*radius)
        let (centers,joins,longs,shorts,rl,separation)=build(gap,samples)
        var points=[SlicePoint]()
        for k in 0..<3 {let inward=Array(shorts[k].reversed());points += points.isEmpty ? inward:Array(inward.dropFirst());points += longs[k].dropFirst()}
        points[points.count-1]=points[0];var clean=[points[0]]
        for q in points.dropFirst() where xyLength(q,clean.last!)>1e-9 {clean.append(q)}
        if xyLength(clean.last!,clean[0])>1e-9 {clean.append(clean[0])}else{clean[clean.count-1]=clean[0]}
        return TripleOutline(points:clean,centers:centers,joins:joins,gap:gap,lobeDiameter:2*rl,centerDistance:separation,actualDiameter:2*clean.map{hypot($0.x,$0.y)}.max()!)
    }
    static func tripleModel(_ p:SliceParameters) throws -> SliceShape {
        guard p["TriplePts"].rounded(.towardZero)==p["TriplePts"] else {throw SliceFailure("每转采样数必须是 50–1000 的整数。")}
        let outline=try tripleOutline(diameter:p["TripleD"],turns:p["TripleTurns"],samples:Int(p["TriplePts"]),rotation:p["TripleRot"])
        let aligned=p.flag("AlignLeft"),path=Polyline(outline.points)
        var seam=0.135
        if aligned {let left=outline.points.dropLast().indices.min{outline.points[$0].x<outline.points[$1].x}!;seam=path.cumulative[left]/path.length}
        let n=min(3000,max(600,Int(ceil(path.length/2)))),turns=turns(p["CH"],p["H0"],p["H"],aligned)
        guard turns>=1 else {throw SliceFailure("高度需包含首层加至少一次完整路径上升。")}
        let count=Int(ceil(turns*Double(n)))
        guard count+n<=180_000 else {throw SliceFailure("路径超过 18 万段，请降低高度或增大每周上升量。")}
        var wall=(0...count).map {i -> SlicePoint in let t=min(Double(i)/Double(n),turns);return path.at(seam+t,z:turnZ(t,p["CH"],p["H0"],p["H"],aligned))}
        wall[wall.count-1].z=p["CH"]
        var ring=(0...n).map{path.at(seam+Double($0)/Double(n),z:p["H0"])},terminal=(0...n).map{path.at(seam+turns+Double($0)/Double(n),z:p["CH"])}
        ring[n]=ring[0];terminal[0]=wall.last!;terminal[n]=wall.last!
        guard outline.gap>=p["W"] else {throw SliceFailure(String(format:"三螺旋的名义间距 %.2f mm 小于线宽 %.2f mm；请增大直径、减少圈数或减小线宽。",outline.gap,p["W"]))}
        guard (1..<wall.count).allSatisfy({xyLength(wall[$0-1],wall[$0])<=p["W"]}) else {throw SliceFailure("路径离散步长超过线宽，请减小尺寸或增加线宽。")}
        var candidate:[String:Any]=["points":coordinates(terminal)]
        if aligned {candidate["gap"]=p["CH"]-p["H0"]-(turns-1)*p["H"]}
        var lines=["; PATH_SCHEMA=G1_GEOMETRY_V1","; SHAPE_KIND=TRIPLE_ARCHIMEDEAN","; HAS_BOTTOM=0","; BOTTOM_PATTERN=NONE","; OUTER_FIX_ELIGIBLE=0","; OUTER_FIX_APPLIED=0","; E_UNITS=VOLUME_MM3","; GINGER_PELLET_FLOW_COEFFICIENT=1","; COMBINED_FLOW_MULTIPLIER=1","; FIRST_LAYER_FLOW_MULTIPLIER=1","; PLACEMENT_CENTER_X=0 PLACEMENT_CENTER_Y=0","; H=\(fmt(p["H"])) W=\(fmt(p["W"]))","; H0=\(fmt(p["H0"])) BH=\(fmt(p["BH"]))","; FIRST_PATH_WIDTH="+fmt(p["W"]),"; BOTTOM_LINE_WIDTH="+fmt(p["W"]),"; BOTTOM_LAYERS=0","; BOTTOM_TOP_Z=0","; TOTAL_HEIGHT="+fmt(p["CH"]),"; EF_AMOUNT=0","; G1_FINISH_CANDIDATE="+(try json(candidate)),"; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH","; ===== PRINT START =====","G90","G21","M83","G92 E0","G1 Z"+fmt(p["H0"])+" F600","G1 X"+fmt(ring[0].x)+" Y"+fmt(ring[0].y)+" F3000","; ===== WALL ====="]
        if aligned {lines.insert("; LEFT_ALIGNED=1",at:1)}
        func emit(_ points:[SlicePoint],_ heights:[Double]) throws {
            let computation=SliceComputation.current
            for (i,h) in heights.enumerated() {if i & 255 == 0 {try computation?.check()};let a=points[i],b=points[i+1],e=xyLength(a,b)*beadArea(p["W"],h);lines += ["; GH_GAP_HEIGHT="+fmt(max(h,0.000001)),"G1 X\(fmt(b.x)) Y\(fmt(b.y)) Z\(fmt(b.z)) E\(fmt(e)) F420"]}
        }
        try emit(ring,Array(repeating:p["H0"],count:n))
        let heights=(0..<wall.count-1).map {i -> Double in
            let mid=(Double(i)/Double(n)+min(Double(i+1)/Double(n),turns))/2
            return aligned ? turnZ(mid,p["CH"],p["H0"],p["H"],true)-turnZ(max(0,mid-1),p["CH"],p["H0"],p["H"],true):p["H"]*min(1,mid)
        }
        try emit(wall,heights);lines.append("; ===== PRINT PATH END =====")
        let info=String(format:"三螺旋 | 路径外接直径 %.2f mm | 名义间距 %.2f mm | 单瓣直径 %.2f mm\n原脚本闭合路径，按弧长连续上升；无底，EF 不参与。",outline.actualDiameter,outline.gap,outline.lobeDiameter)
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:Array(ring.dropLast())+wall,wall:wall,details:["outline":outline,"seam":seam])
    }
    static func pointDistance(_ point:SlicePoint,_ a:SlicePoint,_ b:SlicePoint)->Double {
        let dx=b.x-a.x,dy=b.y-a.y,u=max(0,min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/max(dx*dx+dy*dy,1e-20)))
        return hypot(point.x-a.x-u*dx,point.y-a.y-u*dy)
    }
    @discardableResult static func checkSpacing(_ poly:[SlicePoint],width:Double,closed:Bool=true) throws -> Double {
        if closed {try assertSimple(poly)}
        struct Cell:Hashable {let x:Int;let y:Int};struct Pair:Hashable {let i:Int;let j:Int}
        let count=closed ? poly.count:max(0,poly.count-1)
        var arc=[0.0],grid=[Cell:[Int]](),checked=Set<Pair>(),minimum=Double.infinity
        for i in 0..<count {arc.append(arc.last!+xyLength(poly[i],poly[(i+1)%poly.count]))}
        func cross(_ a:SlicePoint,_ b:SlicePoint,_ c:SlicePoint)->Double {(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}
        for i in 0..<count {
            if i & 63 == 0 {try SliceComputation.check()}
            let a=poly[i],b=poly[(i+1)%poly.count]
            for x in Int(floor((min(a.x,b.x)-width)/width))...Int(floor((max(a.x,b.x)+width)/width)) {
                for y in Int(floor((min(a.y,b.y)-width)/width))...Int(floor((max(a.y,b.y)+width)/width)) {
                    let cell=Cell(x:x,y:y)
                    for j in grid[cell,default:[]] {
                        let pair=Pair(i:i,j:j);if checked.contains(pair) {continue};checked.insert(pair)
                        let separation=abs((arc[i]+arc[i+1]-arc[j]-arc[j+1])/2)
                        if (closed ? min(separation,arc.last!-separation):separation)<3*width {continue}
                        let c=poly[j],d=poly[(j+1)%poly.count]
                        if !closed && cross(a,b,c)*cross(a,b,d)<0 && cross(c,d,a)*cross(c,d,b)<0 {throw SliceFailure("双螺旋路径自交，请减少圈数或增大单瓣直径。")}
                        let distance=min(pointDistance(a,c,d),pointDistance(b,c,d),pointDistance(c,a,b),pointDistance(d,a,b));minimum=min(minimum,distance)
                        if distance<width-0.02 {throw SliceFailure(String(format:closed ? "扩容后相邻料道间距约 %.2f mm，小于线宽 %.2f mm；请增大外接直径、减小每瓣空腔直径或减小线宽。":"双螺旋相邻料道间距 %.2f mm，小于线宽 %.2f mm；请减少圈数、增大单瓣直径或减小线宽。",distance,width))}
                    }
                    grid[cell,default:[]].append(i)
                }
            }
        }
        return minimum
    }
}
