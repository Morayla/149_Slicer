import Foundation

final class FernSliceSections {
    let depth:Double,heights:[Double],sections:[[SlicePoint]],nodes:[(Int,Double)],count:Int
    var fractions:[Double]=[]
    init(_ depth:Double,variant:String,resources:URL) throws {
        struct Profile:Decodable {let depths:[Double];let sections:[[[Double]]];let subdivisions:[Int]}
        let name=variant=="E" ? "fern1060_e_profile":"fern1060_profile"
        let data=try JSONDecoder().decode(Profile.self,from:Data(contentsOf:resources.appendingPathComponent(name+".json")))
        self.depth=depth;heights=data.depths;sections=data.sections.map{$0.map{SlicePoint($0[0],$0[1],0)}};count=sections[0].count
        var nodes=[(Int,Double)]()
        for (i,n) in data.subdivisions.enumerated() {for k in 0..<n {nodes.append((i,Double(k)/Double(n)))}}
        nodes.append(nodes[0]);self.nodes=nodes
        fractions=SliceGeometry.pathFractions(nodes.indices.map{at($0,depth/2)})
    }
    func at(_ index:Int,_ z:Double)->SlicePoint {
        let source=max(0,min(500.5,z/depth*500.5)),j=max(0,min(heights.count-2,SliceGeometry.upperBound(heights,source)-1)),t=(source-heights[j])/(heights[j+1]-heights[j])
        let (i,u)=nodes[index],k=(i+1)%count,a=sections[j],b=sections[j+1]
        let x=(1-t)*((1-u)*a[i].x+u*a[k].x)+t*((1-u)*b[i].x+u*b[k].x)
        let y=(1-t)*((1-u)*a[i].y+u*a[k].y)+t*((1-u)*b[i].y+u*b[k].y)
        return SlicePoint(x,y,z)
    }
}

extension SliceGeometry {
    static func fernModel(_ values:SliceParameters,resources:URL) throws -> SliceShape {
        var p=values;let depth=p["FernDepth"],first=p["H0"],height=p["H"],width=p["W"]
        guard (200...500.5).contains(depth) else {throw SliceFailure("支架打印高度（进深）须在200–500.5 mm；正面1060mm造型不缩放。")}
        guard abs(width-8)<=1e-8 else {throw SliceFailure("此支架轮廓按8mm线宽校准，请保持线宽8mm。")}
        guard height>0,height<=3.5,first>0,first<=3.5 else {throw SliceFailure("此支架的主体及首层层高须不超过3.5mm。")}
        let turns=Int(ceil((depth-first)/height-1e-9)),pitch=(depth-first)/Double(turns),variant=p.text("SourceMode")=="Fern1060E" ? "E":"original"
        let sections=try FernSliceSections(depth,variant:variant,resources:resources),count=(sections.nodes.count-1)*(turns+2)
        guard count<=500_000 else {throw SliceFailure("支架路径约\(count)段，超过本造型50万段上限；请缩短打印高度或增大层高（最大3.5mm）。")}
        p.set(["CH":depth,"HasBottom":0,"EF":0,"EFTable":"","AlignLeft":false])
        let limit=(width-edge*max(height,first))/2
        var lines=helicalHeader(p,kind:variant=="E" ? "FERN1060E":"FERN1060",pitch:pitch,start:sections.at(0,first),metadata:["; FERN1060_POINT_LIMIT=500000"],bottomHeight:first)
        let result=try helicalPath(p,fractions:sections.fractions,marker:nil,lines:&lines,at:sections.at,validate:{points,previous in
            if let previous=previous {
                let delta=previous.last!-points[0]
                guard sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z)<=1e-6 else {throw SliceFailure("支架圈间接缝不连续。")}
                let shift=zip(previous,points).map{xyLength($0,$1)}.max()!
                guard shift<=limit else {throw SliceFailure(String(format:"支架逐圈横移%.3fmm超过搭接限值%.3fmm，请增加进深或降低层高。",shift,limit))}
            }
            for i in 1..<points.count {
                let q=points[i],length=xyLength(points[i-1],q)
                guard q.x.isFinite,q.y.isFinite,q.z.isFinite,length>0,length<=width else {throw SliceFailure("支架路径有无效点或长跳段。")}
            }
        })
        var info=String(format:"圆拱双卷支架 · 1060版 | 正面高1060 × 宽469.9mm | 打印高度（进深）%.1fmm\n原轮廓固定对应，45°居中摆放；8mm线宽；首层等高，主体连续升Z，顶部整平。\n%d段／50万段上限；实际每圈升高%.4fmm；最大逐圈横移%.3fmm（限值%.3f）。\n外围裙边未加入；不含内部清料圈。几何与指令检查不等于实物成形、喷头避让或承载验证。",depth,count,pitch,result.maxShift,limit)
        if variant=="E" {info=info.replacingOccurrences(of:"圆拱双卷支架 · 1060版",with:"圆拱双卷支架 · E版卷尖小减").replacingOccurrences(of:"原轮廓固定对应",with:"沿用原比例，仅缩短两侧卷尖；截面固定对应")}
        let details:[String:Any]=["segments":count,"actual_pitch":pitch,"max_shift":result.maxShift,"overlap_limit":limit,"max_segment":result.maxSegment,"point_limit":500_000]
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:result.wall,wall:result.wall,sectionCount:sections.heights.count,details:["fern1060":details])
    }
}
