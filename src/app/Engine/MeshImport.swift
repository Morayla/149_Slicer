import Foundation
import simd

enum SliceMeshImport {
    static func triangles(file:String,scale:Double,tolerance:Double,stepHelper:URL?=nil) throws -> [[SlicePoint]] {
        let url=URL(fileURLWithPath:(file as NSString).expandingTildeInPath)
        var isDirectory:ObjCBool=false
        guard FileManager.default.fileExists(atPath:url.path,isDirectory:&isDirectory),!isDirectory.boolValue else {throw SliceFailure("模型文件不存在，请重新选择导入文件。")}
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 150_000_000 else {throw SliceFailure("模型文件超过 150 MB，请先简化网格。")}
        guard scale.isFinite,(0.001...1000).contains(scale) else {throw SliceFailure("导入缩放比例必须在 0.001–1000。")}
        let triangles:[[SlicePoint]]
        switch url.pathExtension.lowercased() {
        case "step","stp":
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("149-step-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:folder)}
            let output=folder.appendingPathComponent("mesh.stl")
            let helper=stepHelper ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/149-step")
            do {_=try NativeSliceProcess.run(helper,[url.path,output.path,String(tolerance)])}
            catch {throw SliceFailure("STEP 转换失败："+error.localizedDescription)}
            guard FileManager.default.fileExists(atPath:output.path) else {throw SliceFailure("STEP 转换没有生成有效网格。")}
            triangles=try stl(Data(contentsOf:output))
        case "stl":triangles=try stl(Data(contentsOf:url,options:.mappedIfSafe))
        case "obj":triangles=try obj(String(contentsOf:url,encoding:.utf8))
        default:throw SliceFailure("支持 STL、OBJ、STEP / STP。")
        }
        guard !triangles.isEmpty,triangles.count<=250_000 else {throw SliceFailure("模型为空或超过 250000 个三角面。")}
        var low=SlicePoint(repeating:.infinity),high=SlicePoint(repeating: -.infinity)
        for triangle in triangles {
            guard triangle.count==3 else {throw SliceFailure("模型包含无效三角面。")}
            for p in triangle {
                guard p.x.isFinite,p.y.isFinite,p.z.isFinite else {throw SliceFailure("模型包含无效坐标。")}
                low=simd_min(low,p);high=simd_max(high,p)
            }
        }
        let center=SlicePoint((low.x+high.x)/2,(low.y+high.y)/2,low.z)
        let result=triangles.map{$0.map{($0-center)*scale}}
        guard result.allSatisfy({$0.allSatisfy({p in p.x.isFinite && p.y.isFinite && p.z.isFinite && max(abs(p.x),abs(p.y),abs(p.z))<=1_000_000})}) else {throw SliceFailure("模型坐标或缩放后的尺寸超出支持范围。")}
        return result
    }
    static func stl(_ data:Data) throws -> [[SlicePoint]] {
        let count=data.count>=84 ? data.withUnsafeBytes{Int(UInt32(littleEndian:$0.loadUnaligned(fromByteOffset:80,as:UInt32.self)))}:0
        if count>0 && 84+count*50==data.count {
            guard count<=250_000 else {throw SliceFailure("网格超过 250000 个三角面，请简化。")}
            return data.withUnsafeBytes {raw in
                (0..<count).map {i in
                    (0..<3).map {j in
                        let offset=84+i*50+12+j*12
                        func scalar(_ k:Int)->Double {Double(Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:offset+k*4,as:UInt32.self))))}
                        return SlicePoint(scalar(0),scalar(1),scalar(2))
                    }
                }
            }
        }
        guard let text=String(data:data,encoding:.ascii) else {throw SliceFailure("STL 数据无效。")}
        var vertices=[SlicePoint]()
        for line in text.components(separatedBy:.newlines) {
            let parts=line.split(whereSeparator:{$0.isWhitespace})
            if parts.first?.lowercased()=="vertex" {
                guard parts.count==4,let x=Double(parts[1]),let y=Double(parts[2]),let z=Double(parts[3]) else {throw SliceFailure("STL 包含无效顶点。")}
                vertices.append(SlicePoint(x,y,z))
                if vertices.count>750_000 {throw SliceFailure("网格超过 250000 个三角面，请简化。")}
            }
        }
        guard vertices.count%3==0 else {throw SliceFailure("STL 三角面数据不完整。")}
        return stride(from:0,to:vertices.count,by:3).map{Array(vertices[$0..<$0+3])}
    }
    static func obj(_ text:String) throws -> [[SlicePoint]] {
        var vertices=[SlicePoint](),triangles=[[SlicePoint]]()
        for line in text.components(separatedBy:.newlines) {
            let parts=line.split(separator:"#",omittingEmptySubsequences:false)[0].split(whereSeparator:{$0.isWhitespace})
            guard let kind=parts.first else {continue}
            if kind=="v" {
                guard parts.count>=4,let x=Double(parts[1]),let y=Double(parts[2]),let z=Double(parts[3]) else {throw SliceFailure("OBJ 顶点坐标无效。")}
                vertices.append(SlicePoint(x,y,z))
            } else if kind=="f" {
                var face=[SlicePoint]()
                for token in parts.dropFirst() {
                    guard let number=Int(token.split(separator:"/",omittingEmptySubsequences:false)[0]),number != 0 else {throw SliceFailure("OBJ 顶点索引无效。")}
                    let index=number>0 ? number-1:vertices.count+number
                    guard vertices.indices.contains(index) else {throw SliceFailure("OBJ 顶点索引无效。")}
                    face.append(vertices[index])
                }
                guard face.count==3 || face.count==4 else {throw SliceFailure("OBJ 请三角化后导出；仅支持三角面和凸四边面。")}
                if face.count==4 {
                    let normals=(0..<4).map{simd_cross(face[($0+1)%4]-face[$0],face[($0+2)%4]-face[($0+1)%4])}
                    if normals.dropFirst().contains(where:{simd_dot(normals[0],$0)<=0}) {throw SliceFailure("OBJ 含凹四边面，请先三角化。")}
                }
                for i in 1..<face.count-1 {triangles.append([face[0],face[i],face[i+1]])}
                if triangles.count>250_000 {throw SliceFailure("网格超过 250000 个三角面，请简化。")}
            }
        }
        return triangles
    }
}

final class ImportedSliceSections:SliceSections {
    let height:Double
    let radius:Double
    let triangles:[[SlicePoint]]
    private let bucket:Double
    private var index=[Int:[Int]](),cache=[Double:[SlicePoint]]()
    private(set) var nested=false
    private struct Key:Hashable,Comparable {
        let x:Int64;let y:Int64
        static func <(a:Key,b:Key)->Bool {a.x==b.x ? a.y<b.y:a.x<b.x}
    }
    private struct Edge:Hashable {let a:Key;let b:Key}
    init(_ triangles:[[SlicePoint]],pitch:Double) throws {
        self.triangles=triangles
        height=triangles.flatMap{$0}.map(\.z).max() ?? 0
        radius=triangles.flatMap{$0}.map{hypot($0.x,$0.y)}.max() ?? 0
        guard height>0 else {throw SliceFailure("模型高度必须大于 0。")}
        guard height<=1000,radius<=1000 else {throw SliceFailure("导入模型超出 G1 尺寸范围，请调整缩放比例。")}
        bucket=max(pitch/4,0.05);var references=0
        for (i,triangle) in triangles.enumerated() {
            let a=triangle.map(\.z).min()!,b=triangle.map(\.z).max()!
            if b-a<1e-9 {continue}
            let start=Int(a/bucket),end=Int(b/bucket);references+=end-start+1
            if references>2_000_000 {throw SliceFailure("网格切片索引过大，请简化长条三角面或降低模型高度。")}
            for k in start...end {index[k,default:[]].append(i)}
        }
    }
    func loop(_ requested:Double) throws -> [SlicePoint] {
        let z=max(1e-6,min(height-1e-6,requested)),key=(z*1e8).rounded(.toNearestOrEven)/1e8
        if let result=cache[key] {return result}
        var edges=Set<Edge>(),points=[Key:SlicePoint]()
        func node(_ q:SlicePoint)->Key {
            let k=Key(x:Int64((q.x/1e-5).rounded(.toNearestOrEven)),y:Int64((q.y/1e-5).rounded(.toNearestOrEven)))
            if points[k]==nil {points[k]=q};return k
        }
        for i in index[Int(z/bucket),default:[]] {
            let triangle=triangles[i];var hits=[SlicePoint]()
            for j in 0..<3 {
                let a=triangle[j],b=triangle[(j+1)%3]
                if (a.z<=z && z<b.z) || (b.z<=z && z<a.z) {hits.append(a+((z-a.z)/(b.z-a.z))*(b-a))}
            }
            if hits.count==2 {let a=node(hits[0]),b=node(hits[1]);if a != b {edges.insert(Edge(a:min(a,b),b:max(a,b)))}}
        }
        var graph=[Key:[Key]]()
        for edge in edges {graph[edge.a,default:[]].append(edge.b);graph[edge.b,default:[]].append(edge.a)}
        guard !graph.isEmpty,graph.values.allSatisfy({$0.count==2}) else {throw SliceFailure(String(format:"Z=%.3f 的截面不闭合或网格非流形，请修复模型。",z))}
        var unseen=Set(graph.keys),loops=[[SlicePoint]]()
        while let start=unseen.min() {
            var current=start,previous:Key?,path=[SlicePoint]()
            while true {
                unseen.remove(current);path.append(points[current]!)
                let next=graph[current]!.filter{$0 != previous}.min()!
                previous=current;current=next
                if current==start {break}
                guard unseen.contains(current) else {throw SliceFailure("截面连接异常。")}
            }
            loops.append(SliceGeometry.clean(path))
        }
        loops.sort{abs(SliceGeometry.area($0))>abs(SliceGeometry.area($1))}
        var outer=loops[0]
        if loops.dropFirst().contains(where:{loop in !loop.allSatisfy{SliceGeometry.contains(outer,$0)}}) {throw SliceFailure("当前仅支持单个外轮廓灯罩；检测到分离的多个轮廓。")}
        if loops.count>1 {nested=true}
        if SliceGeometry.area(outer)<0 {outer.reverse()}
        try SliceGeometry.assertSimple(outer);cache[key]=outer;return outer
    }
}

final class EllipseSliceSections:SliceSections {
    let height:Double;let radius:Double
    private let points:[SlicePoint]
    init(_ p:SliceParameters) throws {
        let a=p["EllipseMajor"]/2,b=p["EllipseMinor"]/2
        height=p["CH"];radius=max(a,b)
        var count=max(128,Int(ceil(Double.pi*sqrt(radius/(2*p["Tolerance"])))))
        count=4*Int(ceil(Double(count)/4))
        guard count<=2000 else {throw SliceFailure("椭圆尺寸或精度过高，请减小尺寸或降低精度。")}
        let angle=SliceGeometry.modulo(p["EllipseRotation"],360)*Double.pi/180,c=cos(angle),s=sin(angle)
        points=(0..<count).map{i in let t=SliceGeometry.tau*Double(i)/Double(count),x=a*cos(t),y=b*sin(t);return SlicePoint(x*c-y*s,x*s+y*c,0)}
    }
    func loop(_ z:Double) throws -> [SlicePoint] {points}
}
