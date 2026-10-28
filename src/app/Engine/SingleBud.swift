import Foundation

final class BudSliceSections {
    struct Node {let kind:Int;let u:Double}
    let p:SliceParameters,width:Double,half:Double,radius:Double,inner:Double,start:Double,end:Double,angle:Double,rotation:Double
    let nodes:[Node]
    init(_ p:SliceParameters) throws {
        self.p=p;width=p["W"];half=(p["W"]+p["BudLaneGap"])/2;radius=p["BudD"]/2-half-width/2;inner=p["BudCoreD"]/2+half+width/2
        start=p["BudStart"];end=p["BudEnd"];angle=p["BudCurl"]*Double.pi/180;rotation=p["BudRot"]*Double.pi/180
        guard p["BudLaneGap"]>=0,p["BudCoreD"]>0 else {throw SliceFailure("花蕾双线净间隙须非负，涡心净空直径须大于 0。")}
        guard radius>inner+2*width else {throw SliceFailure("花蕾内卷空间不足，请增大外径、减小涡心净空或双线间隙。")}
        guard (0.75...3).contains(p["BudTurns"]) else {throw SliceFailure("花蕾基准圈数须在 0.75–3 圈之间。")}
        guard (0...180).contains(p["BudCurl"]) else {throw SliceFailure("花蕾收拢角须在 0–180° 之间。")}
        guard p["H0"]<=start,start<end,end<=p["CH"] else {throw SliceFailure("花蕾收拢区间须满足：首层高度 ≤ 开始高度 < 结束高度 ≤ 总高度。")}
        let step=min(2,width/3),count=max(160,Int(ceil((SliceGeometry.tau*p["BudTurns"]+angle)*radius/step))),caps=max(16,Int(ceil(Double.pi*half/step)))
        guard count<=2400 else {throw SliceFailure("花蕾采样过多，请减小尺寸、圈数或提高线宽。")}
        var nodes=(0...count).map{Node(kind:0,u:Double($0)/Double(count))}
        nodes += (1..<caps).map{Node(kind:1,u:Double($0)/Double(caps))};nodes += (0...count).reversed().map{Node(kind:2,u:Double($0)/Double(count))};nodes += (1..<caps).map{Node(kind:3,u:Double($0)/Double(caps))}
        let seam=nodes.indices.min{(nodes[$0].kind==1 ? abs(nodes[$0].u-0.5):2)<(nodes[$1].kind==1 ? abs(nodes[$1].u-0.5):2)}!
        nodes=Array(nodes[seam...])+nodes[..<seam];nodes.append(nodes[0]);self.nodes=nodes
    }
    func at(_ index:Int,_ z:Double)->SlicePoint {
        let node=nodes[index],u=(node.kind==0 || node.kind==2) ? node.u:(node.kind==1 ? 1.0:0.0)
        let t=max(0,min(1,(z-start)/(end-start))),strength=1-t*t*(3-2*t),dr=radius-inner,r=radius-dr*u*u,rp = -2*dr*u
        let a=rotation+SliceGeometry.tau*p["BudTurns"]*u-angle*strength*(1-u)*(1-u),ap=SliceGeometry.tau*p["BudTurns"]+2*angle*strength*(1-u)
        let c=cos(a),s=sin(a),tx=rp*c-r*s*ap,ty=rp*s+r*c*ap,norm=hypot(tx,ty),tangent=SlicePoint(tx/norm,ty/norm,0),normal=SlicePoint(-tangent.y,tangent.x,0)
        let v:SlicePoint
        if node.kind==0 {v=normal}else if node.kind==2 {v = -normal}else{let sign=node.kind==1 ? 1.0:-1.0;v=sign*(cos(Double.pi*node.u)*normal+sin(Double.pi*node.u)*tangent)}
        return SlicePoint(r*c+half*v.x,r*s+half*v.y,z)
    }
    func loop(_ z:Double)->[SlicePoint] {nodes.indices.map{at($0,z)}}
}

extension SliceGeometry {
    static func budModel(_ p:SliceParameters) throws -> SliceShape {
        let first=p["H0"],height=p["CH"],nominal=p["H"],width=p["W"]
        guard height>=first+nominal else {throw SliceFailure("花蕾高度须包含首层和至少一圈墙体。")}
        let sections=try BudSliceSections(p)
        for i in 0...20 {
            let z=sections.start+(sections.end-sections.start)*Double(i)/20
            do {try checkSpacing(Array(sections.loop(z).dropLast()),width:width)}catch{throw SliceFailure(String(format:"花蕾在 Z=%.2f mm 的料道相交或过密；请增大外径、减少圈数 / 收拢角，或减小双线间隙。",z))}
        }
        let path=sections.loop(first),fractions=pathFractions(path),turns=Int(ceil((height-first)/nominal-1e-9)),pitch=(height-first)/Double(turns),limit=(width-edge*max(nominal,first))/2
        guard (path.count-1)*(turns+2)<=240_000 else {throw SliceFailure("花蕾路径超过 24 万段，请降低模块高度、减小尺寸或增大层高。")}
        var lines=helicalHeader(p,kind:"SINGLE_BUD",pitch:pitch,start:path[0],metadata:["; SINGLE_BUD_VASE=1","; SINGLE_BUD_CLOSED=1","; BUD_OPENING_RECESS=UPPER"])
        let result=try helicalPath(p,fractions:fractions,marker:"SINGLE_BUD",lines:&lines,captureLaps:true,at:sections.at,validate:{points,previous in
            if let previous=previous {
                let delta=previous.last!-points[0]
                guard sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z)<=1e-7 else {throw SliceFailure("花蕾连续圈衔接失败。")}
                let shift=zip(previous,points).map{xyLength($0,$1)}.max()!
                guard shift<=limit else {throw SliceFailure(String(format:"花蕾每圈横向移动 %.2f mm，超过当前搭接限值 %.2f mm；请减小层高 / 收拢角或加长收拢高度区间。",shift,limit))}
            }
            var projected=points.map{SlicePoint($0.x,$0.y,0)};if xyLength(points[0],points.last!)<1e-8 {projected.removeLast()}
            do {try checkSpacing(projected,width:width)}catch {throw SliceFailure("花蕾连续上升路径过密，请减小层高、圈数或收拢角。")}
        })
        let info=String(format:"单螺旋花蕾 | 参考外径 %.1f mm | 高 %.1f mm | 收拢 %.1f°\n侧面 S 形卷边：涡心固定，外侧出口随高度平滑移动；不是等截面直筒。\n单个螺旋、双壁闭合：卷入 → 内端圆弧折返 → 卷出 → 外端闭合；首层等高，墙体连续升 Z。\n每圈升高 %.4f mm，共 %d 圈；最大逐圈横移 %.3f mm，规划限值 %.3f mm。\n双线净间隙 %.1f mm；每道线宽 %.1f mm。顶部补齐剩余间隙。\n概念造型：保留花蕾卷边特征，非参考图片的精确复刻；未验证颗粒成形、喷嘴碰撞与结构强度。\n本模块无实心底、无贯穿立柱实体；EF、首层外缘校准及叠加波形不参与。",p["BudD"],height,p["BudCurl"],pitch,turns,result.maxShift,limit,p["BudLaneGap"],width)
        let details:[String:Any]=["layers":result.laps,"sections":sections,"actual_pitch":pitch,"rise_turns":turns,"max_shift":result.maxShift,"overlap_limit":limit,"fractions":fractions]
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:result.wall,wall:result.wall,sectionCount:turns,details:["bud":details])
    }
}
