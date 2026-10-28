import Foundation
import Darwin
import simd

typealias SlicePoint = SIMD3<Double>

struct SliceFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct SliceParameters {
    var values: [String: Any]
    init(_ values: [String: Any]) { self.values = values }
    subscript(_ key: String) -> Double {
        get { (values[key] as? NSNumber)?.doubleValue ?? Double(values[key] as? String ?? "") ?? 0 }
        set { values[key] = newValue }
    }
    func flag(_ key: String, fallback: Bool = false) -> Bool {
        guard let value = values[key] else { return fallback }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        return !["", "false", "0", "off", "no"].contains(String(describing: value).lowercased())
    }
    func text(_ key: String, fallback: String = "") -> String { values[key] as? String ?? fallback }
    mutating func set(_ changes: [String: Any]) { values.merge(changes) { _, new in new } }
}

protocol SliceSections: AnyObject {
    var height: Double { get }
    var radius: Double { get }
    func loop(_ z: Double) throws -> [SlicePoint]
}

struct SliceShape {
    var gcode: String
    var info: String
    var parameters: SliceParameters
    var points: [SlicePoint]
    var wall: [SlicePoint]
    var bottoms: [[SlicePoint]] = []
    var volumes: [[Double?]] = []
    var source: SliceSections?
    var sectionCount = 0
    var details: [String: Any] = [:]
}

enum SliceGeometry {
    static let tau = 2 * Double.pi
    static let edge = 1 - Double.pi / 4
    static func fmt(_ value:Double,places:Int=6)->String {
        withUnsafeTemporaryAllocation(of:CChar.self,capacity:128) {buffer in
            let count=withVaList([places,value]) {vsnprintf(buffer.baseAddress!,128,"%.*f",$0)}
            guard count>=0,count<128 else {
                var text=String(format:"%.*f",places,value)
                if places>0 {while text.last=="0" {text.removeLast()};if text.last=="." {text.removeLast()}}
                return text.isEmpty || text=="-0" ? "0":text
            }
            var end=Int(count)
            if places>0 {while end>0 && buffer[end-1]==48 {end-=1};if end>0 && buffer[end-1]==46 {end-=1}}
            if end==0 || (end==2 && buffer[0]==45 && buffer[1]==48) {return "0"}
            buffer[end]=0;return String(cString:buffer.baseAddress!)
        }
    }
    static func smooth(_ value: Double) -> Double {
        let u = min(1, max(0, value)); return u * u * (3 - 2 * u)
    }
    static func integralSmooth(_ u: Double) -> Double { pow(u, 3) - 0.5 * pow(u, 4) }
    static func xyLength(_ a: SlicePoint, _ b: SlicePoint) -> Double { hypot(a.x-b.x, a.y-b.y) }
    static func beadArea(_ width: Double, _ height: Double) -> Double { height * (width - height * edge) }
    static func turns(_ height: Double, _ base: Double, _ pitch: Double, _ aligned: Bool) -> Double {
        let result = (height-base)/pitch; return aligned ? ceil(result-1e-9) : result
    }
    static func turnZ(_ t: Double, _ height: Double, _ base: Double, _ pitch: Double, _ aligned: Bool) -> Double {
        guard aligned else { return base+pitch*t }
        let last = max(0, turns(height,base,pitch,true)-1)
        return base+pitch*min(t,last)+(height-base-last*pitch)*max(0,t-last)
    }
    static func modulo(_ value: Double, _ modulus: Double) -> Double {
        let r=value.truncatingRemainder(dividingBy:modulus);return r<0 ? r+modulus:r
    }
    static func upperBound(_ values: [Double], _ value: Double) -> Int {
        var low=0,high=values.count
        while low<high { let mid=(low+high)/2;if value<values[mid] {high=mid} else {low=mid+1} }
        return low
    }
    static func json(_ value: Any) throws -> String {
        let bytes=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.fragmentsAllowed,.withoutEscapingSlashes])
        return String(decoding:bytes,as:UTF8.self)
    }
    static func coordinates(_ points: [SlicePoint]) -> [[Double]] { points.map { [$0.x,$0.y,$0.z] } }
    static func area(_ polygon: [SlicePoint]) -> Double {
        guard !polygon.isEmpty else{return 0}
        return polygon.indices.reduce(0) { sum,i in let a=polygon[i],b=polygon[(i+1)%polygon.count];return sum+a.x*b.y-a.y*b.x }/2
    }
    static func contains(_ polygon: [SlicePoint], _ q: SlicePoint) -> Bool {
        var inside=false
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count]
            if (a.y>q.y) != (b.y>q.y),q.x<(b.x-a.x)*(q.y-a.y)/(b.y-a.y)+a.x {inside.toggle()}
        }
        return inside
    }
    static func clean(_ points: [SlicePoint]) -> [SlicePoint] {
        var out=[SlicePoint]()
        for q in points where out.isEmpty || simd_distance(q,out.last!)>1e-7 {out.append(q)}
        if out.count>1,simd_distance(out[0],out.last!)<1e-7 {out.removeLast()}
        var changed=true
        while changed && out.count>3 {
            changed=false;var result=[SlicePoint]()
            for i in out.indices {
                let a=out[(i+out.count-1)%out.count],b=out[i],c=out[(i+1)%out.count],u=b-a,v=c-b
                if abs(u.x*v.y-u.y*v.x)<1e-7*(hypot(u.x,u.y)+hypot(v.x,v.y)) && u.x*v.x+u.y*v.y>=0 {changed=true}
                else {result.append(b)}
            }
            out=result
        }
        return out
    }
    private struct Cell: Hashable {let x:Int;let y:Int}
    private struct Pair: Hashable {let a:Int;let b:Int}
    static func assertSimple(_ polygon: [SlicePoint]) throws {
        let cell=max(1,sqrt(abs(area(polygon)))/20)
        var grid=[Cell:[Int]](),checked=Set<Pair>()
        func cross(_ a:SlicePoint,_ b:SlicePoint,_ c:SlicePoint)->Double {(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count]
            for x in Int(floor(min(a.x,b.x)/cell))...Int(floor(max(a.x,b.x)/cell)) {
                for y in Int(floor(min(a.y,b.y)/cell))...Int(floor(max(a.y,b.y)/cell)) {
                    let key=Cell(x:x,y:y)
                    for j in grid[key,default:[]] {
                        let pair=Pair(a:i,b:j),delta=(i-j+polygon.count)%polygon.count
                        if checked.contains(pair) || delta==1 || delta==polygon.count-1 {continue}
                        checked.insert(pair)
                        let c=polygon[j],d=polygon[(j+1)%polygon.count]
                        if cross(a,b,c)*cross(a,b,d)<(-1e-12) && cross(c,d,a)*cross(c,d,b)<(-1e-12) {
                            throw SliceFailure("轮廓或内缩路径自交，请减小 EF / 线宽或简化模型。")
                        }
                    }
                    grid[key,default:[]].append(i)
                }
            }
        }
    }
    static func offset(_ input:[SlicePoint],_ distance:Double) throws -> [SlicePoint] {
        var polygon=clean(input)
        if area(polygon)<0 {polygon.reverse()}
        guard polygon.count>=3 else {throw SliceFailure("轮廓内缩后消失。")}
        var out=[SlicePoint]();out.reserveCapacity(polygon.count)
        for i in polygon.indices {
            let a=polygon[(i+polygon.count-1)%polygon.count],b=polygon[i],c=polygon[(i+1)%polygon.count]
            var u=b-a,v=c-b
            u.z=0;v.z=0
            let lu=hypot(u.x,u.y),lv=hypot(v.x,v.y)
            guard lu>0,lv>0 else {throw SliceFailure("轮廓包含重复顶点。")}
            u/=lu;v/=lv
            let p=SlicePoint(b.x-u.y*distance,b.y+u.x*distance,b.z)
            let q=SlicePoint(b.x-v.y*distance,b.y+v.x*distance,b.z)
            let denominator=u.x*v.y-u.y*v.x
            let r=abs(denominator)<1e-10 ? p:p+u*((q.x-p.x)*v.y-(q.y-p.y)*v.x)/denominator
            if distance>0 && (xyLength(r,b)>max(10*distance,1) || !contains(polygon,r)) {
                throw SliceFailure("轮廓内缩失败：局部过窄或尖角过大。")
            }
            out.append(r)
        }
        guard area(out)>1e-4 else {throw SliceFailure("轮廓内缩后消失。")}
        try assertSimple(out);return out
    }
    static func sampledPolygon(_ input:[SlicePoint],z:Double,count:Int,angle:Double)->[SlicePoint] {
        var poly=input
        if area(poly)<0 {poly.reverse()}
        let dx=cos(angle),dy=sin(angle)
        var hit:(Double,Int,SlicePoint)?
        for i in poly.indices {
            let a=poly[i],b=poly[(i+1)%poly.count],vx=b.x-a.x,vy=b.y-a.y,den=dx*vy-dy*vx
            if abs(den)<=1e-10 {continue}
            let t=(a.x*vy-a.y*vx)/den,u=(a.x*dy-a.y*dx)/den
            if t>=0 && u>=(-1e-8) && u<=1+1e-8 && (hit==nil || t>=hit!.0) {hit=(t,i,SlicePoint(t*dx,t*dy,z))}
        }
        let path:[SlicePoint]
        if let (_,i,q)=hit {path=[q]+Array(poly[(i+1)...])+Array(poly[...i])+[q]}
        else {let i=poly.indices.min{poly[$0].x<poly[$1].x} ?? 0;path=Array(poly[i...])+Array(poly[..<i])+[poly[i]]}
        var lengths=[0.0]
        for i in 1..<path.count {lengths.append(lengths.last!+xyLength(path[i-1],path[i]))}
        return (0..<count).map {i in
            let distance=lengths.last!*Double(i)/Double(count)
            let j=min(path.count-2,max(0,upperBound(lengths,distance)-1))
            let fraction=(distance-lengths[j])/max(1e-12,lengths[j+1]-lengths[j])
            var q=path[j]+fraction*(path[j+1]-path[j]);q.z=z;return q
        }
    }
    struct Ribbon {var low:Double;var high:Double;var top:Double}
    static func paintRibbon(_ ledger:inout [Ribbon],low:Double,high:Double,top:Double,angleStep:Double)->(Double,Double) {
        var cuts=[low,high],outside=[Ribbon]()
        for r in ledger {
            if r.high<=low || r.low>=high {outside.append(r)}
            else {
                cuts += [max(r.low,low),min(r.high,high)]
                if r.low<low {outside.append(Ribbon(low:r.low,high:low,top:r.top))}
                if r.high>high {outside.append(Ribbon(low:high,high:r.high,top:r.top))}
            }
        }
        cuts=Array(Set(cuts)).sorted()
        var inside=[Ribbon](),volume=0.0,maxGap=0.0
        for i in 1..<cuts.count {
            let a=cuts[i-1],b=cuts[i]
            if b-a<=1e-12 {continue}
            let mid=(a+b)/2,previous=ledger.first{$0.low<=mid && mid<=$0.high}?.top ?? 0,gap=max(0,top-previous)
            volume+=gap*(b*b-a*a)*0.5*angleStep;maxGap=max(maxGap,gap)
            inside.append(Ribbon(low:a,high:b,top:max(top,previous)))
        }
        var merged=[Ribbon]()
        for r in (outside+inside).sorted(by:{$0.low == $1.low ? $0.high<$1.high:$0.low<$1.low}) {
            if let last=merged.last,abs(last.high-r.low)<1e-10,abs(last.top-r.top)<1e-10 {merged[merged.count-1].high=r.high}
            else {merged.append(r)}
        }
        ledger=merged;return (volume,maxGap)
    }
}
