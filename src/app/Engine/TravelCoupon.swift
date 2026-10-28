import Foundation

extension SliceGeometry {
    static func travelContour()->[SlicePoint] {
        let span=1.75*Double.pi,half=(8.0+1.2)/2
        var spine=(0...480).map{i -> SlicePoint in let t=span*Double(i)/480,r=20.6+23.4*pow(t/span,4),a = -Double.pi/2-t;return SlicePoint(r*cos(a),r*sin(a),0)}
        let v=spine.last!-spine[spine.count-2],angle = -atan2(v.y,v.x),c=cos(angle),s=sin(angle);spine=spine.map{SlicePoint($0.x*c-$0.y*s,$0.x*s+$0.y*c,0)}
        let end=spine.last!;spine += (1...25).map{end+SlicePoint(Double($0),0,0)}
        let normals=spine.indices.map{i -> SlicePoint in let d=spine[min(spine.count-1,i+1)]-spine[max(0,i-1)],length=hypot(d.x,d.y);return SlicePoint(-d.y/length,d.x/length,0)}
        let left=zip(spine,normals).map{$0+half*$1},right=zip(spine,normals).map{$0-half*$1},tip=spine.last!
        var points=(0...20).map{i in let t=Double.pi*Double(i)/40;return tip+SlicePoint(half*cos(t),half*sin(t),0)}
        points += left.dropLast().reversed()
        let n=normals[0],tangent=SlicePoint(n.y,-n.x,0),core=spine[0]
        points += (1...40).map{i in let t=Double.pi*Double(i)/40;return core+half*(cos(t)*n-sin(t)*tangent)}
        points += right.dropFirst();points += (1...20).map{i in let t = -Double.pi/2+Double.pi*Double(i)/40;return tip+SlicePoint(half*cos(t),half*sin(t),0)}
        points[points.count-1]=points[0];let origin=points[0];return points.map{$0-origin}
    }
    static func travelModel(_ values:SliceParameters) throws -> SliceShape {
        var p=values;let distance=p["TravelTestSpan"],requested=p["TravelTestRounds"]
        guard (80...700).contains(distance) else {throw SliceFailure("测试跨孔距离请输入 80–700 mm。")}
        guard requested.rounded(.towardZero)==requested,(3...40).contains(requested) else {throw SliceFailure("测试往返轮数请输入 3–40 的整数。")}
        let rounds=Int(requested),height=2.5+Double(rounds)*3.5,local=travelContour()
        p.set(["W":8,"H":3.5,"H0":2.5,"CH":height,"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false])
        let paths=[local.map{SlicePoint(-distance/2+$0.x,$0.y,0)},local.map{SlicePoint(distance/2-$0.x,$0.y,0)}],points=paths[0]+paths[1]
        let bounds=[points.map{$0.x}.min()!-4,points.map{$0.y}.min()!-4,points.map{$0.x}.max()!+4,points.map{$0.y}.max()!+4]
        guard max(bounds[2]-bounds[0],bounds[3]-bounds[1])<=980 else {throw SliceFailure("测试件超出平台范围，请减小跨孔距离。")}
        let lengths=(1..<local.count).map{xyLength(local[$0-1],local[$0])},fractions=pathFractions(local)
        var lines=["; PATH_SCHEMA=G1_GEOMETRY_V1","; SHAPE_KIND=TRAVEL_TEST","; TRAVEL_TEST_VASE=1","; HAS_BOTTOM=0","; BOTTOM_LAYERS=0","; OUTER_FIX_ELIGIBLE=0","; EF_AMOUNT=0","; E_UNITS=VOLUME_MM3","; GINGER_PELLET_FLOW_COEFFICIENT=1","; COMBINED_FLOW_MULTIPLIER=1","; FIRST_LAYER_FLOW_MULTIPLIER=1","; H=3.5 W=8","; H0=2.5 BH=3.5","; FIRST_PATH_WIDTH=8","; BOTTOM_LINE_WIDTH=8","; TOTAL_HEIGHT="+fmt(height),"; PLACEMENT_CENTER_X=0 PLACEMENT_CENTER_Y=0","; TEST_AIR_DISTANCE="+fmt(distance),"; TEST_ROUNDS=\(rounds)","; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH","; ===== PRINT START =====","G90","G21","M83","G92 E0"]
        var wall=[SlicePoint](),transfers=0,previous:SlicePoint?
        func emit(_ side:Int,_ base:Double,_ rise:Double,_ gaps:[Double],_ label:String) {
            let path=zip(paths[side],fractions).map{SlicePoint($0.x,$0.y,base+rise*$1)},start=path[0]
            lines += ["; TEST_ISLAND=\(side)","; TEST_STAGE="+label]
            if let previous=previous {let d=previous-start;if sqrt(d.x*d.x+d.y*d.y+d.z*d.z)>1e-8 {transfers+=1;lines += ["; TEST_CROSSING=\(transfers)","G0 X\(fmt(start.x)) Y\(fmt(start.y)) Z\(fmt(start.z)) F3000"]}}else{lines += ["G0 Z"+fmt(start.z)+" F600","G0 X\(fmt(start.x)) Y\(fmt(start.y)) F3000"]}
            lines.append("; ===== WALL =====")
            for i in 1..<path.count {let q=path[i],h=(gaps[i-1]+gaps[i])/2,e=lengths[i-1]*h*(8-edge*h);lines += ["; GH_GAP_HEIGHT="+fmt(h),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(e)) F540"]}
            previous=path.last!;wall+=path
        }
        lines += [";LAYER_CHANGE","; GH_WALL_TURN=0"]
        for side in 0..<2 {emit(side,2.5,0,Array(repeating:2.5,count:local.count),"FIRST")}
        for turn in 0..<rounds {lines += [";LAYER_CHANGE","; GH_WALL_TURN=\(turn+1)","; TEST_ROUND=\(turn+1)"];let gaps=turn==0 ? fractions.map{3.5*$0}:Array(repeating:3.5,count:local.count);for side in 0..<2 {emit(side,2.5+Double(turn)*3.5,3.5,gaps,"SPIRAL")}}
        lines += [";LAYER_CHANGE","; GH_WALL_TURN=\(rounds+1)"]
        for side in 0..<2 {lines.append("; GH_RIM_FINISH_START");emit(side,height,0,fractions.map{3.5*(1-$0)},"RIM");lines.append("; GH_RIM_FINISH_END")}
        lines += ["; TRAVEL_TEST_RIMS_DONE=2","; ===== PRINT PATH END ====="]
        let info=String(format:"跨孔空移测试 · 两座矮卷芯\n跨孔起停点距离 %.0f mm；主体重复 %d 轮，含首层和收口共 %d 次跨孔空移。\n占地约 %.1f × %.1f mm；打印高 %.1f mm。\n固定：线宽8 mm，双墙净隙1.2 mm，每圈升高3.5 mm，首层2.5 mm；打印9 mm/s，空移抬升6 mm。\n每侧独立螺旋升Z，两侧交替；起停点放在面向开孔的外露端，不在卷芯孔内。\n外围先打印一圈裙边，裙边速度9 mm/s；回抽量、恢复量和温度沿用当前G1设置。螺旋段停挤不会向下回擦；首层及平顶可沿等高路径擦拭。\n观察外露起停点堆料、重启缺料、孔间拉丝，以及卷芯和双墙缝内残料。\n仅测试局部截面与低高度空移，不包含底梁开孔分裂过渡；不代表完整跨度、高件稳定性或喷头实体碰撞已经通过。",distance,rounds,transfers,bounds[2]-bounds[0],bounds[3]-bounds[1],height)
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:wall,wall:wall,sectionCount:1,details:["travel_test":["bounds":bounds,"rounds":rounds,"transfers":transfers,"height":height,"distance":distance,"paths":paths]])
    }
}
