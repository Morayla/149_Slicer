import Foundation

final class FixedSliceSections:SliceSections {
    let points:[SlicePoint],height:Double,radius:Double
    init(_ points:[SlicePoint],height:Double) {self.points=points;self.height=height;radius=points.map{hypot($0.x,$0.y)}.max() ?? 0}
    func loop(_ z:Double) throws -> [SlicePoint] {points}
}

extension SliceGeometry {
    static func innerPocket(_ outline:TripleOutline) throws -> (Double,SlicePoint) {
        let poly=Array(outline.points.dropLast()),center=outline.centers[0],gap=outline.gap,other=outline.centers[1],rotation=atan2(other.y-center.y,other.x-center.x),ca=cos(rotation),sa=sin(rotation)
        let edges=poly.indices.filter{xyLength(poly[$0],center)<3*gap}.map{(poly[$0],poly[($0+1)%poly.count])}
        var best=(0.0,center),mid=center,span=0.65*gap
        for _ in 0..<4 {
            for i in 0...20 {for j in 0...20 {
                let a=(Double(i)/10-1)*span,b=(Double(j)/10-1)*span,q=SlicePoint(mid.x+a*ca-b*sa,mid.y+a*sa+b*ca,0)
                if xyLength(q,center)>1.2*gap {continue}
                let distance=edges.map{pointDistance(q,$0.0,$0.1)}.min()!
                if distance>best.0 && contains(poly,q) {best=(distance,q)}
            }}
            mid=best.1;span/=5
        }
        guard best.0>=0.1*gap else {throw SliceFailure("无法识别三螺旋的内部空间。")};return best
    }
    struct VaseMorph {
        let centers:[SlicePoint],offsets:[SlicePoint],radius:Double,core:Double,target:Double,translationCore:Double,slopes:[Double]
        init(_ outline:TripleOutline,width:Double,diameter:Double) throws {
            centers=outline.centers;radius=min(4.5*outline.gap,0.49*outline.centerDistance)
            let pocket=try innerPocket(outline);core=pocket.0;target=max(core,(diameter+width)/2)
            guard core<=target,target<radius*0.8 else {throw SliceFailure("每瓣空腔直径超出当前三瓣尺寸的可用范围；请调整空腔直径或增大外接直径。")}
            let off=pocket.1-centers[0]
            offsets=(0..<3).map{let a=Double($0)*tau/3,c=cos(a),s=sin(a);return SlicePoint(off.x*c-off.y*s,off.x*s+off.y*c,0)}
            translationCore=max(0.4,(hypot(off.x,off.y)+core)/radius+0.02)
            guard translationCore<0.9 else {throw SliceFailure("内部空间的定位超出平滑变形范围。")}
            let d0=target/core,d1=(radius-target)/(radius-core);var slopes=[d0,2*d0*d1/(d0+d1),1.0]
            for (i,d) in [d0,d1].enumerated() {let total=slopes[i]+slopes[i+1];if total>3*d {let scale=3*d/total;slopes[i]*=scale;slopes[i+1]*=scale}}
            self.slopes=slopes
        }
        func radial(_ r:Double)->Double {
            let xs=[0,core,radius],ys=[0,target,radius],i=r<core ? 0:1,h=xs[i+1]-xs[i],t=(r-xs[i])/h
            return (2*pow(t,3)-3*t*t+1)*ys[i]+(pow(t,3)-2*t*t+t)*h*slopes[i]+(-2*pow(t,3)+3*t*t)*ys[i+1]+(pow(t,3)-t*t)*h*slopes[i+1]
        }
        func at(_ q:SlicePoint,_ strength:Double)->SlicePoint {
            if strength<=0 {return q}
            for (center,off) in zip(centers,offsets) {
                var x=q.x-center.x,y=q.y-center.y
                if hypot(x,y)>=radius {continue}
                for _ in 0..<24 {let f=1-smooth((hypot(x,y)-radius*translationCore)/(radius*(1-translationCore)));x-=strength*off.x/24*f;y-=strength*off.y/24*f}
                let r=hypot(x,y)
                if r>0 && r<radius {let scale=1+strength*(radial(r)/r-1);x*=scale;y*=scale}
                return SlicePoint(x+center.x,y+center.y,q.z)
            }
            return q
        }
    }
    static func rayEnvelope(_ poly:[SlicePoint],n:Int=720) throws -> [SlicePoint] {
        var result=[SlicePoint]()
        for i in 0..<n {
            let angle=tau*Double(i)/Double(n),dx=cos(angle),dy=sin(angle);var radii=[Double]()
            for j in poly.indices {
                let a=poly[j],b=poly[(j+1)%poly.count],vx=b.x-a.x,vy=b.y-a.y,den=dx*vy-dy*vx
                if abs(den)<1e-12 {continue};let r=(a.x*vy-a.y*vx)/den,u=(a.x*dy-a.y*dx)/den
                if r>=0 && u>=0 && u<=1 {radii.append(r)}
            }
            guard let r=radii.max() else {throw SliceFailure("三瓣底部外轮廓未闭合。")};result.append(SlicePoint(r*dx,r*dy,0))
        }
        return clean(result)
    }
    static func solidFootprint(_ poly:[SlicePoint],halfWidth:Double,n:Int=720) throws -> [SlicePoint] {
        let envelope=try rayEnvelope(poly,n:n);var sides=[(SlicePoint,SlicePoint)]()
        for i in envelope.indices {
            let a=envelope[i],b=envelope[(i+1)%envelope.count],dx=b.x-a.x,dy=b.y-a.y,length=hypot(dx,dy),normal=SlicePoint(-dy/length*halfWidth,dx/length*halfWidth,0)
            for sign in [-1.0,1.0] {sides.append((a+sign*normal,b+sign*normal))}
        }
        var result=[SlicePoint]()
        for i in 0..<n {
            let angle=tau*Double(i)/Double(n),dx=cos(angle),dy=sin(angle);var radius=0.0
            for q in envelope {let dot=q.x*dx+q.y*dy,cross=q.x*dy-q.y*dx,delta=halfWidth*halfWidth-cross*cross;if delta>=0 {radius=max(radius,dot+sqrt(delta))}}
            for (a,b) in sides {let vx=b.x-a.x,vy=b.y-a.y,den=dx*vy-dy*vx;if abs(den)<1e-12 {continue};let r=(a.x*vy-a.y*vx)/den,u=(a.x*dy-a.y*dx)/den;if r>=0 && u>=0 && u<=1 {radius=max(radius,r)}}
            guard radius>0 else {throw SliceFailure("三瓣底部外轮廓无效。")};result.append(SlicePoint(radius*dx,radius*dy,0))
        }
        result=clean(result);try assertSimple(result);return result
    }
    static func tripleVaseModel(_ p:SliceParameters) throws -> SliceShape {
        let height=p["CH"],base=p["H0"]+(p["B"]-1)*p["BH"],pitch=p["H"],vaseTurns=p.values["VaseTurns"]==nil ? 3:p["VaseTurns"]
        guard height>=base+pitch else {throw SliceFailure("总高度必须包含完整底部和至少一个墙体层高。")}
        guard p["VaseCoreDiameter"]>0 else {throw SliceFailure("每瓣空腔直径必须大于 0。")}
        guard vaseTurns.isFinite,(1...6).contains(vaseTurns) else {throw SliceFailure("每瓣螺旋圈数须在 1–6 圈之间，可输入小数，例如 2.5。")}
        let outline=try tripleOutline(diameter:p["VaseD"],turns:vaseTurns,samples:Int(p["TriplePts"]),rotation:p["TripleRot"]),morph=try VaseMorph(outline,width:p["W"],diameter:p["VaseCoreDiameter"]),path=Polyline(outline.points.map{morph.at($0,1)})
        let angle=p.flag("AlignLeft") ? Double.pi:modulo(p["SeamAngle"],360)*Double.pi/180
        let seamIndex=(0..<path.points.count-1).max{path.points[$0].x*cos(angle)+path.points[$0].y*sin(angle)<path.points[$1].x*cos(angle)+path.points[$1].y*sin(angle)}!
        let seam=path.cumulative[seamIndex]/path.length,n=max(600,min(6000,Int(ceil(path.length/min(p["W"]/6,1.25))))),reference=(0..<n).map{path.at(seam+Double($0)/Double(n))}
        try checkSpacing(reference,width:p["W"])
        let footprint=try solidFootprint(Array(outline.points.dropLast()),halfWidth:p["W"]/2)
        let (bottoms,volumes,gaps)=try buildBottom(p,FixedSliceSections(footprint,height:height),720,angle)
        let turns=turns(height,base,pitch,true),count=Int(turns)*n
        guard count+bottoms.reduce(0,{$0+$1.count})+n<=220_000 else {throw SliceFailure("三螺旋花瓶路径超过 22 万段，请降低高度、增大层高或减小尺寸。")}
        let wall=(0...count).map{i -> SlicePoint in let t=Double(i)/Double(n);return path.at(seam+t,z:turnZ(t,height,base,pitch,true))}
        let maxShift=(n..<wall.count).map{xyLength(wall[$0],wall[$0-n])}.max()!
        guard (1..<wall.count).allSatisfy({xyLength(wall[$0-1],wall[$0])<=p["W"]}) else {throw SliceFailure("三螺旋路径采样不足，请减小尺寸或增加线宽。")}
        var terminal=(0...n).map{path.at(seam+Double($0)/Double(n),z:height)};terminal[0]=wall.last!;terminal[n]=wall.last!
        let candidate:[String:Any]=["points":coordinates(terminal),"gap":height-base-(turns-1)*pitch]
        var lines=["; PATH_SCHEMA=G1_GEOMETRY_V1","; SHAPE_KIND=TRIPLE_VASE","; VASE_TURNS_PER_LOBE="+fmt(vaseTurns),"; HAS_BOTTOM=1","; BOTTOM_KIND=SOLID","; BOTTOM_PATTERN=ZIGZAG","; BOTTOM_ANGLES="+(try layerAngles(p)).map{fmt($0)}.joined(separator:","),"; OUTER_FIX_ELIGIBLE=0","; OUTER_FIX_APPLIED=0","; EF_AMOUNT=0","; E_UNITS=VOLUME_MM3","; GINGER_PELLET_FLOW_COEFFICIENT=1","; COMBINED_FLOW_MULTIPLIER=1","; FIRST_LAYER_FLOW_MULTIPLIER=1","; PLACEMENT_CENTER_X=0 PLACEMENT_CENTER_Y=0","; H=\(fmt(pitch)) W=\(fmt(p["W"]))","; H0=\(fmt(p["H0"])) BH=\(fmt(p["BH"]))","; FIRST_PATH_WIDTH="+fmt(p["WB"]),"; BOTTOM_LINE_WIDTH="+fmt(p["WB"]),"; BOTTOM_LAYERS=\(Int(p["B"]))","; BOTTOM_TOP_Z="+fmt(base),"; TOTAL_HEIGHT="+fmt(height),"; G1_FINISH_CANDIDATE="+(try json(candidate)),"; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH","; ===== PRINT START =====","G90","G21","M83","G92 E0","G1 Z"+fmt(bottoms[0][0].z)+" F600","G1 X\(fmt(bottoms[0][0].x)) Y\(fmt(bottoms[0][0].y)) F3000","; ===== BOTTOM ====="]
        if p.flag("AlignLeft") {lines.insert("; LEFT_ALIGNED=1",at:1)}
        func travel(_ q:SlicePoint) {lines.append("G0 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) F3000")}
        func emit(_ q:SlicePoint,_ volume:Double?,_ h:Double) {guard let e=volume else{travel(q);return};lines += ["; GH_GAP_HEIGHT="+fmt(max(h,1e-6)),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(e)) F420"]}
        for (i,points) in bottoms.enumerated() {lines.append("; BOTTOM_LAYER=\(i+1)");if i>0 {travel(points[0])};for j in 1..<points.count {emit(points[j],volumes[i][j-1],gaps[i][j-1])}}
        travel(wall[0]);lines.append("; ===== WALL =====")
        for i in 0..<wall.count-1 {if i%n==0 {lines.append("; GH_WALL_TURN=\(i/n)")};let mid=(Double(i)+0.5)/Double(n),h=turnZ(mid,height,base,pitch,true)-turnZ(max(0,mid-1),height,base,pitch,true);emit(wall[i+1],xyLength(wall[i],wall[i+1])*beadArea(p["W"],h),h)}
        lines.append("; ===== PRINT PATH END =====")
        let top=Array(terminal.dropLast()),clearance=2*top.indices.map{pointDistance(morph.centers[0],top[$0],top[($0+1)%top.count])}.min()!-p["W"]
        guard clearance>=p["VaseCoreDiameter"]-0.15 else {throw SliceFailure("每瓣空腔的路径采样误差过大，请增加每转采样数。")}
        let transfers=volumes.map{String($0.filter{$0==nil}.count)}.joined(separator:" / ")
        let info=String(format:"三螺旋花瓶 | 每瓣 %g 圈 | 高 %.2f mm | 底 %d 层 / %.2f mm\n每瓣空腔净直径约 %.2f mm，上下截面一致；不再随高度变化。\n完整三瓣实心底采用连续 Zigzag；填满中心和螺旋间隙。各底层内部空移次数：%@（含接外轮廓）。\n墙体连续上升；本造型暂不应用 EF、首层外缘校准或三角波。\n几何封底不等于不漏水，请用实物静置试水；尚未校验打印头外形碰撞。",vaseTurns,height,Int(p["B"]),base,clearance,transfers)
        let details:[String:Any]=["spiral_turns":vaseTurns,"footprint":footprint,"top":top,"clearance":clearance,"max_shift":maxShift,"n":n,"turns":turns]
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:bottoms.flatMap{$0}+wall,wall:wall,bottoms:bottoms,volumes:volumes,sectionCount:1,details:["outline":outline,"seam":seam,"vase":details])
    }
}
