import Foundation

extension SliceGeometry {
    struct WaveVertex {var t:Double;var point:SlicePoint;init(_ t:Double,_ point:SlicePoint){self.t=t;self.point=point}}
    struct WaveSettings {let count:Double,amplitude:Double,negative:Double,start:Int,pattern:[Int],source:Bool,fit:[String:Any]?}
    typealias WaveSection=(Double,Double)throws->SlicePoint
    static func waveSettings(_ raw:SliceParameters,mode:String) throws -> WaveSettings? {
        if !raw.flag("WaveEnabled") {return nil}
        guard ["WaveAmp","WaveNegAmp","WaveCount","WaveStartLayer"].allSatisfy({raw[$0].isFinite && raw[$0]>=0}) else {throw SliceFailure("波形参数必须是非负有限数值。")}
        let text=raw.text("WavePattern").trimmingCharacters(in:.whitespacesAndNewlines),tokens=text.components(separatedBy:CharacterSet(charactersIn:",，;；").union(.whitespacesAndNewlines)).filter{!$0.isEmpty}
        guard !tokens.isEmpty,tokens.allSatisfy({["0","1","2"].contains($0)}) else {throw SliceFailure("波形排列只接受 0、1、2，用逗号、空格或换行分隔。")}
        guard tokens.count<=256 else {throw SliceFailure("波形排列最多 256 项。")}
        let pattern=tokens.map{Int($0)!},alternating=pattern.count%2==0 && pattern.indices.allSatisfy{let a=pattern[$0],b=pattern[($0+1)%pattern.count];return a != b && a != 0 && b != 0}
        var n=raw["WaveCount"],fit:[String:Any]?
        guard n != 1 else {throw SliceFailure("闭合三角波至少需要每遍 2 个波；1 个波会退化成穿过模型的往返直线。")}
        if raw.flag("WaveAutoFit") && ["Cylinder","Ellipse","Cone"].contains(mode) && (2...1000).contains(n) {
            let fitted:Double,kind:String
            if alternating {fitted=min(999.5,max(2.5,ceil(n)-0.5));kind="continuous_alternating"}else if Set(pattern).count==1 && pattern[0] != 0 {fitted=min(1000,max(2,floor(n+0.5)));kind="repeated"}else{fitted=min(1000,max(2,floor(n+0.5)));kind="transitions"}
            fit=["requested":n,"effective":fitted,"kind":kind];n=fitted
        }
        guard (2...1000).contains(n),(n*2).rounded(.towardZero)==n*2 else {throw SliceFailure("每遍波数须为 2–1000 的整数或半整数（例如 39.5）。")}
        guard raw["WaveStartLayer"].rounded(.towardZero)==raw["WaveStartLayer"],(0...10000).contains(raw["WaveStartLayer"]) else {throw SliceFailure("WaveStartLayer 超出范围或不是整数。")}
        guard n.rounded(.towardZero)==n || alternating else {throw SliceFailure("半整数波数使用连续交错走线，排列须为 1,2 或 2,1 交替；原形过渡请使用「前几遍保持原形」。")}
        guard ["Source","Continuous"].contains(raw.text("WaveZMode")) else {throw SliceFailure("未知的波形 Z 走法。")}
        return WaveSettings(count:n,amplitude:raw["WaveAmp"],negative:raw["WaveNegAmp"],start:Int(raw["WaveStartLayer"]),pattern:pattern,source:raw.text("WaveZMode")=="Source",fit:fit)
    }
    static func seamPhase(_ t:Double,_ phase:Double,_ n:Double)->Double {let span=min(0.5,2/n),u=min(1,max(0,min(t,1-t)/span));return phase*u*u*(3-2*u)}
    static func lengthLookup(_ fn:(Double)throws->SlicePoint,_ n:Int) throws -> (Double)->Double {
        let points=try (0...n).map{try fn(Double($0)/Double(n))};var lengths=[0.0]
        for i in 1..<points.count {lengths.append(lengths.last!+xyLength(points[i-1],points[i]))}
        return {f in if f<=0{return 0};if f>=1{return 1};let target=f*lengths.last!,i=lowerBound(lengths,target),span=lengths[i]-lengths[i-1];return span>1e-12 ? (Double(i-1)+(target-lengths[i-1])/span)/Double(n):Double(i-1)/Double(n)}
    }
    static func triangleVertices(_ base:(Double)throws->SlicePoint,_ normal:(SlicePoint,Double)throws->SIMD2<Double>,_ n:Int,_ amplitude:Double,_ negative:Double,_ source:Bool,arcLength:Bool=true) throws -> [WaveVertex] {
        let lookup=arcLength ? try lengthLookup(base,max(1200,n*120)):{$0};var vertices=[WaveVertex]()
        for k in 0..<n {
            let ts=[lookup(Double(k)/Double(n)),lookup((Double(k)+0.5)/Double(n)),lookup(Double(k+1)/Double(n))],points=try ts.map(base),z=points[1].z
            for i in 0..<3 where vertices.isEmpty || i>0 {let t=ts[i],q=points[i],d=[-negative,amplitude,-negative][i],normal=try normal(q,t);vertices.append(WaveVertex(t,SlicePoint(q.x+d*normal.x,q.y+d*normal.y,source ? z:q.z)))}
        }
        return vertices
    }
    static func densify(_ vertices:[WaveVertex],limit:Double=1.5)->[WaveVertex] {
        var out=[vertices[0]]
        for i in 1..<vertices.count {let a=vertices[i-1],b=vertices[i],n=max(1,Int(ceil(distance3(a.point,b.point)/limit)));for j in 1...n {let f=Double(j)/Double(n);out.append(WaveVertex(a.t+(b.t-a.t)*f,a.point+(b.point-a.point)*f))}}
        return out
    }
    static func waveVertexAt(_ vertices:[WaveVertex],_ t:Double)->SlicePoint {
        if t<=vertices[0].t {return vertices[0].point};if t>=vertices.last!.t {return vertices.last!.point}
        var lo=0,hi=vertices.count;while lo<hi {let mid=(lo+hi)/2;if vertices[mid].t<t {lo=mid+1}else{hi=mid}}
        let a=vertices[lo-1],b=vertices[lo],f=(t-a.t)/(b.t-a.t);return a.point+(b.point-a.point)*f
    }
    static func connectVertices(_ input:[WaveVertex],_ start:SlicePoint,_ end:SlicePoint,_ fraction:Double,_ n:Double,_ source:Bool)->[WaveVertex] {
        var vertices=input;vertices[0]=WaveVertex(0,start);vertices[vertices.count-1]=WaveVertex(1,end)
        if fraction>=1 {return vertices}
        let q=waveVertexAt(vertices,fraction);var clipped=vertices.filter{$0.t<fraction}+[WaveVertex(fraction,q)]
        if source {
            let anchorT=max(0,fraction-0.5/n),anchor=waveVertexAt(clipped,anchorT),targetZ=start.z+(end.z-start.z)*fraction,tail=clipped.filter{$0.t>anchorT}
            clipped=clipped.filter{$0.t<anchorT}+[WaveVertex(anchorT,anchor)]
            for v in tail {let f=(v.t-anchorT)/(fraction-anchorT);var point=v.point;point.z=anchor.z+(targetZ-anchor.z)*f;clipped.append(WaveVertex(v.t,point))}
        }
        return clipped
    }
    static func crossingRadius(_ radius:Double,_ n:Double,_ amplitude:Double,_ negative:Double)->Double {let inner=radius-negative,outer=radius+amplitude;return 2*inner*outer*cos(Double.pi/(2*n))/(inner+outer)}
    static func circularWaveVertices(_ section:WaveSection,_ layer:Int,_ mode:Int,_ n:Double,_ amplitude:Double,_ negative:Double,_ source:Bool,_ fraction:Double) throws -> [WaveVertex] {
        let a=try section(Double(layer),0),b=try section(Double(layer+1),0),r0=hypot(a.x,a.y),r1=hypot(b.x,b.y),angle=atan2(a.y,a.x),shift=mode==1 ? -0.25:0.25
        func integral(_ x:Double)->Double {let k=floor(x);return 0.5*k+min(x-k,0.5)}
        func rise(_ t:Double)->Double {2*(integral(n*t-shift)-integral(-shift))/n}
        let endRise=source ? rise(fraction):fraction
        func zAt(_ t:Double)->Double {let u=source && endRise>1e-12 ? rise(t)*fraction/endRise:t;return a.z+(b.z-a.z)*u}
        func boundary(_ t:Double)->SlicePoint {let r=crossingRadius(r0+(r1-r0)*t,n,amplitude,negative);return SlicePoint(r*cos(angle),r*sin(angle),zAt(t))}
        var vertices=[WaveVertex(0,boundary(0))]
        for k in 0..<Int(2*n+2) {let t=(0.5*Double(k)+shift)/n;if t<=0 || t>=1 {continue};let radius=r0+(r1-r0)*t+(k%2==1 ? amplitude:-negative),theta=angle+tau*t;vertices.append(WaveVertex(t,SlicePoint(radius*cos(theta),radius*sin(theta),zAt(t))))}
        vertices.append(WaveVertex(1,boundary(1)))
        if fraction<1 {var q=waveVertexAt(vertices,fraction);q.z=a.z+(b.z-a.z)*fraction;vertices=vertices.filter{$0.t<fraction}+[WaveVertex(fraction,q)]}
        return vertices
    }
    static func globalWaveVertices(_ section:WaveSection,layer:Int,start:Int,total:Double,n:Double,firstMode:Int,amplitude:Double,negative:Double,source:Bool,fraction:Double,pointAt:((Double,Double)throws->SlicePoint)?=nil,heightAt:((Double)->Double)?=nil) throws -> [WaveVertex] {
        let phase=firstMode==1 ? 0.0:0.5,duration=total-Double(start)
        func integral(_ s:Double)->Double {let k=floor(s);return 0.5*k+min(s-k,0.5)}
        func rise(_ t:Double)->Double {integral(n*t+phase)-integral(phase)}
        let endRise=rise(duration)
        func vertex(_ k:Int) throws -> WaveVertex {
            let t=(Double(k)*0.5-phase)/n,progress=Double(start)+t,j=max(0,floor(progress)),u=progress-j,a=try section(j,0),b=try section(j+1,0),displacement=k%2 != 0 ? amplitude:-negative
            let radius=hypot(a.x,a.y)*(1-u)+hypot(b.x,b.y)*u+displacement,angle=atan2(a.y,a.x)+tau*progress,zp=Double(start)+(source && endRise>1e-12 ? duration*rise(t)/endRise:t),z=try heightAt?(zp) ?? section(zp,0).z
            var q=try pointAt?(progress,displacement) ?? SlicePoint(radius*cos(angle),radius*sin(angle),0);q.z=z;return WaveVertex(progress,q)
        }
        let lo=Double(layer),hi=lo+fraction,first=Int(floor(2*(n*(lo-Double(start))+phase)+1e-9)),last=Int(ceil(2*(n*(hi-Double(start))+phase)-1e-9)),vertices=try (first...last).map(vertex)
        var end=waveVertexAt(vertices,hi);if hi>=total-1e-10 {end.z=try section(total,0).z}
        return [WaveVertex(0,waveVertexAt(vertices,lo))]+vertices.filter{$0.t>lo+1e-10 && $0.t<hi-1e-10}.map{WaveVertex($0.t-lo,$0.point)}+[WaveVertex(fraction,end)]
    }
}

final class WaveSupportIndex {
    struct Cell:Hashable {let x:Int;let y:Int}
    struct Segment {let a:SlicePoint;let b:SlicePoint;let progress:(Double,Double)?}
    let cell:Double
    var grid=[Cell:[Int]](),segments=[Segment]()
    init(width:Double) {cell=width}
    func extend(_ points:[SlicePoint],_ progress:[Double]) {if points.count>1 {for i in 1..<points.count {add(points[i-1],points[i],(progress[i-1],progress[i]))}}}
    func add(_ a:SlicePoint,_ b:SlicePoint,_ progress:(Double,Double)?) {
        let index=segments.count;segments.append(Segment(a:a,b:b,progress:progress))
        for x in Int(floor(min(a.x,b.x)/cell))...Int(floor(max(a.x,b.x)/cell)) {for y in Int(floor(min(a.y,b.y)/cell))...Int(floor(max(a.y,b.y)/cell)) {grid[Cell(x:x,y:y),default:[]].append(index)}}
    }
    func height(_ q:SlicePoint,fallback:Double,progress:Double?=nil)->(Double,Double) {
        let x=Int(floor(q.x/cell)),y=Int(floor(q.y/cell));var ids=Set<Int>(),best=Double.infinity,height=fallback
        for i in x-2...x+2 {for j in y-2...y+2 {ids.formUnion(grid[Cell(x:i,y:j),default:[]])}}
        for i in ids.sorted() {
            let segment=segments[i],a=segment.a,b=segment.b,dx=b.x-a.x,dy=b.y-a.y,d=dx*dx+dy*dy,u=d != 0 ? min(1,max(0,((q.x-a.x)*dx+(q.y-a.y)*dy)/d)):0
            if let progress=progress,let span=segment.progress {let age=progress-(span.0+u*(span.1-span.0));if age<0.5 || age>1.5 {continue}}
            let distance=pow(q.x-a.x-u*dx,2)+pow(q.y-a.y-u*dy,2)
            if distance<best {best=distance;height=a.z+u*(b.z-a.z)}
        }
        return (height,sqrt(best))
    }
}
