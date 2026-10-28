import Foundation

extension SliceGeometry {
    static func saddleHeight(_ z:Double,_ angle:Double,_ p:SliceParameters)->Double {
        let f=smooth((z-p["NPStart"])/(p["CH"]-p["NPStart"])),c=cos(angle-p["NPDirection"]*Double.pi/180)
        return z-p["NPDepth"]*f*c*c
    }
    static func nonplanarModel(_ values:SliceParameters,source:SliceSections?=nil) throws -> SliceShape {
        var p=values
        for (key,value) in [("NPDepth",15.0),("NPStart",40.0),("NPDirection",90.0)] {
            if p.values[key]==nil {p.set([key:value])}
            guard p[key].isFinite else {throw SliceFailure(key+" 必须是有限数值。")}
        }
        let base=p.flag("HasBottom") ? p["H0"]+(p["B"]-1)*p["BH"]:p["H0"],height=p["CH"],pitch=p["H"]
        guard p["NPDepth"]>=0 else {throw SliceFailure("口沿下凹深度不能为负数。")}
        guard base+pitch<=p["NPStart"],p["NPStart"]<height else {throw SliceFailure("起伏开始高度必须至少高于底部一个层高，并低于总高度。")}
        guard 1.5*p["NPDepth"]<height-p["NPStart"] else {throw SliceFailure("下凹过深或过渡过短，会使相邻圈重合；请减小深度或降低起伏开始高度。")}
        var model=try circularModel(p,source:source);p=model.parameters
        let nominalWall=model.wall,turns=turns(height,base,pitch,true),n=Int((Double(nominalWall.count-1)/turns).rounded(.toNearestOrEven))
        let phase=p.flag("AlignLeft") ? Double.pi:modulo(p["SeamAngle"],360)*Double.pi/180
        func mapped(_ q:SlicePoint)->SlicePoint {SlicePoint(q.x,q.y,saddleHeight(q.z,atan2(q.y,q.x),p))}
        func nominal(_ t:Double)->Double {turnZ(max(0,min(turns,t)),height,base,pitch,true)}
        let wall=nominalWall.map(mapped)
        var gaps=[Double](),volumes=[Double]()
        for i in 0..<wall.count-1 {
            let t=(Double(i)+0.5)/Double(n),angle=phase+tau*t,gap=saddleHeight(nominal(t),angle,p)-saddleHeight(nominal(t-1),angle,p)
            guard gap>0,gap<=p["W"] else {throw SliceFailure("非平面路径的局部间隙无效。")}
            gaps.append(gap);volumes.append(xyLength(wall[i],wall[i+1])*beadArea(p["W"],gap))
        }
        guard let candidate=SliceGcode.meta(model.gcode,"G1_FINISH_CANDIDATE"),let object=try JSONSerialization.jsonObject(with:Data(candidate.utf8)) as? [String:Any],let points=object["points"] as? [[Double]] else {throw SliceFailure("Missing nonplanar rim")}
        var rim=points.map{mapped(SlicePoint($0[0],$0[1],$0[2]))};rim[0]=wall.last!;rim[rim.count-1]=wall.last!
        var rimGaps=[Double](),rimVolumes=[Double](),references=[Double]()
        for i in 0..<rim.count-1 {
            let u=(Double(i)+0.5)/Double(n),angle=phase+tau*u,gap=saddleHeight(height,angle,p)-saddleHeight(nominal(turns-1+u),angle,p)
            guard gap>0,gap<=p["W"] else {throw SliceFailure("口沿收口间隙无效。")}
            references.append(saddleHeight(height,angle,p)-saddleHeight(nominal(turns-1),angle,p));rimGaps.append(gap);rimVolumes.append(xyLength(rim[i],rim[i+1])*beadArea(p["W"],gap))
        }
        let parts=model.gcode.components(separatedBy:"; ===== WALL =====")
        let prefix=SliceGcode.lines(parts[0]).filter{!$0.hasPrefix("; G1_FINISH_CANDIDATE=")}.joined(separator:"\n")
        var lines=[prefix,"; NONPLANAR_RIM_REFERENCE_GAPS="+(try json(references)),"; NONPLANAR_MODE=SADDLE_RIM_V1","; NONPLANAR_DEPTH="+fmt(p["NPDepth"]),"; NONPLANAR_START="+fmt(p["NPStart"]),"; NONPLANAR_DIRECTION="+fmt(p["NPDirection"]),"; ===== WALL ====="]
        if !p.flag("HasBottom") {
            var count=0
            for line in SliceGcode.lines(parts[1]) {if count==n {break};lines.append(line);if line.hasPrefix("G1 ") && line.contains(" E") {count+=1}}
        }
        func emit(_ q:SlicePoint,_ e:Double,_ gap:Double) {lines += ["; GH_GAP_HEIGHT="+fmt(gap),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(e)) F420"]}
        for i in 0..<volumes.count {if i%n==0 {lines.append("; GH_WALL_TURN=\(i/n)")};emit(wall[i+1],volumes[i],gaps[i])}
        lines += ["; GH_WALL_TURN=\(Int(turns))","; NONPLANAR_RIM_START"]
        for i in 0..<rimVolumes.count {emit(rim[i+1],rimVolumes[i],rimGaps[i])}
        lines += ["; NONPLANAR_RIM_END","; ===== PRINT PATH END ====="]
        let allWall=wall+rim.dropFirst(),slope=(0..<allWall.count-1).map{abs(allWall[$0+1].z-allWall[$0].z)/max(xyLength(allWall[$0],allWall[$0+1]),1e-12)}.max()!
        let priorWall=(model.details["wallPath"] as? [SlicePoint]) ?? nominalWall
        model.gcode=lines.joined(separator:"\n");model.wall=allWall;model.points=model.bottoms.flatMap{$0}+allWall
        model.details["wallPath"]=(p.flag("HasBottom") ? []:priorWall.prefix(n).map(mapped))+allWall
        model.details["nonplanar"]=["n":n,"turns":Int(turns),"gaps":gaps,"rim_gaps":rimGaps,"max_slope":slope] as [String:Any]
        model.info+=String(format:"\n非平面口沿：最高 %.2f / 最低 %.2f mm；开始高度 %.2f mm；下凹方向 %.1f°。",height,height-p["NPDepth"],p["NPStart"],modulo(p["NPDirection"],360))
        model.info+=String(format:"\n按相邻圈垂直间隙计算挤出；自动收尾沿完整起伏口沿单次渐减，保留设定的末端流量比例；最大路径倾角 %.1f°。",atan(slope)*180/Double.pi)
        model.info+="\n实验路径：喷嘴保持竖直，尚未校验喷嘴外形及打印头与模型的碰撞。"
        return model
    }
}
