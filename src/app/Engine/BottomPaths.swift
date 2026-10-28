import Foundation
import simd

extension SliceGeometry {
    static func limitedRibbon(_ ledger:inout [Ribbon],radius:Double,halfWidth:Double,top:Double,angleStep:Double,limit:Double)->(Double,Double) {
        func trial(_ width:Double)->([Ribbon],Double,Double) {
            var state=ledger
            let (volume,gap)=paintRibbon(&state,low:max(0,radius-width),high:radius+width,top:top,angleStep:angleStep)
            return (state,volume,gap)
        }
        var (state,volume,gap)=trial(halfWidth)
        if volume>limit {
            var low=0.0,high=halfWidth
            for _ in 0..<32 {
                let mid=(low+high)/2,(candidate,v,g)=trial(mid)
                if v<=limit {low=mid;state=candidate;volume=v;gap=g} else {high=mid}
            }
            if low==0 {return (0,0)}
        }
        ledger=state;return (volume,gap)
    }
    static func segmentInside(_ poly:[SlicePoint],_ a:SlicePoint,_ b:SlicePoint,tolerance:Double=1e-7)->Bool {
        let dx=b.x-a.x,dy=b.y-a.y,length2=dx*dx+dy*dy
        if length2<tolerance*tolerance {return true}
        var cuts=[0.0,1.0]
        for i in poly.indices {
            let c=poly[i],d=poly[(i+1)%poly.count],vx=d.x-c.x,vy=d.y-c.y,den=dx*vy-dy*vx
            if abs(den)<1e-12 {continue}
            let cx=c.x-a.x,cy=c.y-a.y,t=(cx*vy-cy*vx)/den,u=(cx*dy-cy*dx)/den
            if t>0 && t<1 && u >= -tolerance && u<=1+tolerance {cuts.append(t)}
        }
        cuts.sort()
        for i in 1..<cuts.count {
            let low=cuts[i-1],high=cuts[i]
            if high-low<1e-10 {continue}
            let t=(low+high)/2,q=SlicePoint(a.x+t*dx,a.y+t*dy,0)
            if contains(poly,q) {continue}
            var boundary=false
            for j in poly.indices {
                let c=poly[j],d=poly[(j+1)%poly.count],vx=d.x-c.x,vy=d.y-c.y
                let u=max(0,min(1,((q.x-c.x)*vx+(q.y-c.y)*vy)/max(vx*vx+vy*vy,1e-20)))
                if hypot(q.x-c.x-u*vx,q.y-c.y-u*vy)<=tolerance {boundary=true;break}
            }
            if !boundary {return false}
        }
        return true
    }
    static func zigzagChains(_ rows:[[[SlicePoint]]],_ poly:[SlicePoint],_ pitch:Double)->[[SlicePoint]] {
        struct Position:Hashable {let row:Int;let index:Int}
        var used=Set<Position>(),chains=[[SlicePoint]]()
        for (row,intervals) in rows.enumerated() {
            for (index,line) in intervals.enumerated() {
                let position=Position(row:row,index:index)
                if used.contains(position) {continue}
                var chain=line,current=row;used.insert(position)
                while current+1<rows.count {
                    var best:(Double,Int,[SlicePoint])?
                    for (j,next) in rows[current+1].enumerated() {
                        if used.contains(Position(row:current+1,index:j)) {continue}
                        let distance=simd_distance(chain.last!,next[0])
                        if distance<=4*pitch && segmentInside(poly,chain.last!,next[0]) && (best==nil || distance<best!.0) {best=(distance,j,next)}
                    }
                    guard let (_,j,next)=best else {break}
                    chain+=next;current+=1;used.insert(Position(row:current,index:j))
                }
                chains.append(chain)
            }
        }
        return chains
    }
    static func layerAngles(_ p:SliceParameters) throws -> [Double] {
        let n=Int(p["B"])
        var result=(0..<n).map{modulo(p["FillAngle"]+Double($0)*p["FillAngleStep"],180)},seen=Set<Int>()
        let raw=p.text("FillAngles").trimmingCharacters(in:.whitespacesAndNewlines)
        if raw.isEmpty {return result}
        let regex=try NSRegularExpression(pattern:#"^(\d+)\s*[:=]\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))$"#)
        for row in raw.replacingOccurrences(of:";",with:"\n").components(separatedBy:.newlines) {
            let line=String(row.split(separator:"#",omittingEmptySubsequences:false)[0]).trimmingCharacters(in:.whitespaces)
            if line.isEmpty {continue}
            let text=line as NSString
            guard let pair=regex.firstMatch(in:line,range:NSRange(location:0,length:text.length)),let i=Int(text.substring(with:pair.range(at:1))),let value=Double(text.substring(with:pair.range(at:2))) else {throw SliceFailure("逐层角度格式为「1:45」，每行一层。")}
            guard i>=1,i<=n,!seen.contains(i),value.isFinite else {throw SliceFailure("逐层角度层号重复、超出底部层数或角度无效。")}
            seen.insert(i);result[i-1]=modulo(value,180)
        }
        return result
    }
    static func buildBottom(_ p:SliceParameters,_ source:SliceSections?,_ n:Int,_ angle:Double) throws -> ([[SlicePoint]],[[Double?]],[[Double]]) {
        var layers=[[SlicePoint]](),volumes=[[Double?]](),gaps=[[Double]]()
        let solid=p.text("BottomKind",fallback:"Annular")=="Solid",pattern=p.text("BottomPattern",fallback:"Spiral")
        let straight=["Monotonic","Zigzag"].contains(pattern),angles=straight ? try layerAngles(p):[]
        if pattern=="Zigzag" && !solid {throw SliceFailure("连续 Zigzag 暂仅支持实心底。")}
        var ledgers=Array(repeating:[Ribbon](),count:n)
        for layer in 0..<Int(p["B"]) {
            let z=p["H0"]+Double(layer)*p["BH"],h=layer==0 ? p["H0"]:p["BH"],w=p["WB"],pitch=w-h*edge
            let boundary=try inward(loopAt(source,z,p),w/2+p["EF"],z,p),outer=sampled(boundary,n,angle:angle)
            var points=[SlicePoint](),es=[Double?](),hs=[Double]()
            func stroke(_ poly:[SlicePoint],_ ev:[Double]?=nil,_ hv:[Double]?=nil) {
                guard let first=poly.first else{return}
                if points.isEmpty {points.append(first)}
                else if simd_distance(points.last!,first)>1e-8 {points.append(first);es.append(nil);hs.append(0)}
                for i in 0..<max(0,poly.count-1) {
                    let a=poly[i],b=poly[i+1],distance=xyLength(a,b)
                    if distance<1e-9 {continue}
                    let count=straight ? 1:max(1,Int(ceil(distance/min(w/2,1.5))))
                    let volume=ev?[i] ?? distance*beadArea(w,h)
                    for j in 1...count {points.append(a+(b-a)*Double(j)/Double(count));es.append(volume/Double(count));hs.append(hv?[i] ?? h)}
                }
            }
            if straight {
                let poly=outer.map{SlicePoint($0.x,$0.y,0)},inner=solid ? 0:p["Din"]/2+w/2
                if inner>0 && (!contains(poly,.zero) || (0..<64).contains(where:{!contains(poly,SlicePoint(inner*cos(tau*Double($0)/64),inner*sin(tau*Double($0)/64),0))})) {throw SliceFailure("内孔超出底部轮廓。")}
                if inner>0 {stroke((0...n).map{let a=angle+tau*Double($0)/Double(n);return SlicePoint(inner*cos(a),inner*sin(a),z)})}
                // Let independent straight strokes overlap the perimeter by ending
                // inside its footprint. Keeping a full bead pitch between centerlines
                // leaves gaps around their rounded ends, especially at oblique angles.
                let insetDistance=pattern=="Monotonic" ? min(pitch*0.95,w*0.25):pitch*0.95
                let inset=try offset(poly,insetDistance),theta=angles[layer]*Double.pi/180,c=cos(theta),s=sin(theta)
                let rot=inset.map{SlicePoint($0.x*c+$0.y*s,-$0.x*s+$0.y*c,0)}
                let low=rot.map(\.y).min()!,high=rot.map(\.y).max()!,count=max(1,Int(floor((high-low)/pitch))+1)
                let start=(low+high-Double(count-1)*pitch)/2
                var rows=[[[SlicePoint]]]()
                for row in 0..<count {
                    let yy=start+Double(row)*pitch;var hits=[Double]()
                    for i in rot.indices {
                        let a=rot[i],b=rot[(i+1)%rot.count]
                        if (a.y<=yy && yy<b.y) || (b.y<=yy && yy<a.y) {hits.append(a.x+(yy-a.y)*(b.x-a.x)/(b.y-a.y))}
                    }
                    hits.sort()
                    guard hits.count%2==0 else {throw SliceFailure("底部截线连接失败。")}
                    var intervals=stride(from:0,to:hits.count,by:2).map{(hits[$0],hits[$0+1])}
                    let avoid=inner>0 ? inner+pitch*0.95:0
                    if abs(yy)<avoid {
                        let hx=sqrt(avoid*avoid-yy*yy);var pieces=[(Double,Double)]()
                        for (a,b) in intervals {if a < -hx {pieces.append((a,min(b,-hx)))};if b>hx {pieces.append((max(a,hx),b))}}
                        intervals=pieces
                    }
                    if row%2 != 0 {intervals=intervals.reversed().map{($0.1,$0.0)}}
                    rows.append(intervals.filter{abs($0.1-$0.0)>0.05}.map{[SlicePoint($0.0,yy,0),SlicePoint($0.1,yy,0)]})
                }
                let chains=pattern=="Zigzag" ? zigzagChains(rows,rot,pitch):rows.flatMap{$0}
                for chain in chains {stroke(chain.map{SlicePoint($0.x*c-$0.y*s,$0.x*s+$0.y*c,z)})}
                stroke(outer+[outer[0]])
            } else {
                let radii=try radialBoundary(boundary,n,angle,p),inner=solid ? 0:(p["Din"]+w)/2
                guard radii.min()!>inner+p["Tolerance"] else {throw SliceFailure("内孔、线宽或 EF 使底部空间不足。")}
                let outerRadius=radii.max()!,profile=try radialProfile(inner:inner,outer:outerRadius,pitch:w-max(p["H0"],p["BH"])*edge,ease:p["BlendAngle"]/360,open:solid)
                let steps=Int((profile.total*Double(n)).rounded(.toNearestOrEven)),outward=(Int(p["B"])-1-layer)%2==0
                var pts=[SlicePoint](),rr=[Double]()
                for i in 0...steps {
                    let t=Double(i)/Double(n)
                    let value=outward ? profile.radius(t):(solid ? profile.radius(profile.total-t):inner+outerRadius-profile.radius(t))
                    let r=inner+(value-inner)/(outerRadius-inner)*(radii[i%n]-inner),a=angle+tau*modulo(t,1)
                    pts.append(SlicePoint(r*cos(a),r*sin(a),z));rr.append(r)
                }
                var ev=[Double](),hv=[Double]()
                for i in 0..<steps {
                    let r=(rr[i]+rr[i+1])/2,distance=xyLength(pts[i],pts[i+1]);var radial=pitch
                    if source != nil {radial*=sqrt(1+pow((rr[i+1]-rr[i])/(max(r,1e-5)*tau/Double(n)),2))}
                    var volume:Double,gap:Double
                    if distance<1e-9 {volume=0;gap=h}
                    else if solid && source != nil {
                        (volume,gap)=limitedRibbon(&ledgers[i%n],radius:r,halfWidth:min(radial/2,(w+distance)/2),top:z,angleStep:tau/Double(n),limit:distance*beadArea(w,h))
                    } else {
                        (volume,gap)=paintRibbon(&ledgers[i%n],low:max(0,r-radial/2),high:max(0,r+radial/2),top:z,angleStep:tau/Double(n))
                        if solid {volume=min(volume,distance*beadArea(w,h))}
                    }
                    if distance<1e-9 {volume=0}
                    ev.append(volume);hv.append(max(gap,1e-6))
                }
                stroke(pts,ev,hv)
            }
            guard !points.isEmpty else {throw SliceFailure("底部没有可打印路径。")}
            layers.append(points);volumes.append(es);gaps.append(hs)
        }
        return (layers,volumes,gaps)
    }
}
