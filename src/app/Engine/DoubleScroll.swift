import Foundation

extension SliceGeometry {
    static func doubleVaseModel(_ values:SliceParameters,outlineData:([SlicePoint],[String:Any])?=nil) throws -> SliceShape {
        var p=values
        let width=p["W"],first=p["H0"],height=p["CH"],nominal=p["H"]
        guard outlineData != nil || p["DoubleProfile"]==3 else {throw SliceFailure("花瓶走线请选择「等距双螺旋（平顺）」轮廓。")}
        guard height>=first+nominal else {throw SliceFailure("花瓶总高度需包含首层及至少一个完整墙体层高。")}
        let lane=p.values["DoubleLaneGap"]==nil ? 9:p["DoubleLaneGap"],inset=(width+lane)/2
        var (path,info)=try outlineData ?? returnOutline(p["DoubleD"],p["DoubleTurns"],p["DoubleGap"],width,lane,p["DoubleRot"],profile:3,innerFloor:inset+width)
        path=alignedLoop(Array(path.dropLast()),p.flag("AlignLeft"))
        let fractions=pathFractions(path),perimeter=(1..<path.count).reduce(0){$0+xyLength(path[$1-1],path[$1])},turns=max(1,Int(ceil((height-first)/nominal-1e-9))),pitch=(height-first)/Double(turns)
        guard (path.count-1)*(turns+2)<=220_000 else {throw SliceFailure("双螺旋花瓶路径超过 22 万段，请降低高度、减少圈数或增大层高。")}
        let compensation=try ScrollCompensation(path,&p,Double(turns)),start=compensation.at(0,time:0)
        var lines=helicalHeader(p,kind:"DOUBLE_SCROLL",pitch:pitch,start:start,metadata:["; DOUBLE_PROFILE=FAIR_ARCHIMEDEAN_SCROLL","; DOUBLE_VASE=1","; DOUBLE_LINES=3","; DOUBLE_CLOSED=1","; DOUBLE_TURNS_PER_SIDE="+fmt(p["DoubleTurns"]),"; DOUBLE_EDGE_GAP="+fmt(p["DoubleGap"]),"; DOUBLE_VASE_ACTUAL_PITCH="+fmt(pitch)])
        lines.removeAll{$0.hasPrefix("; EF_")};lines.insert(contentsOf:compensation.metadata,at:lines.firstIndex(of:"; E_UNITS=VOLUME_MM3")!)
        let result=try helicalPath(p,fractions:fractions,marker:"DOUBLE_VASE",lines:&lines,captureLaps:true,at:{i,z in
            var q=compensation.at(i,time:(z-first)/pitch);q.z=z;return q
        },validate:compensation.checkLap)
        var lapGaps=[[Double]](),lapVolumes=[[Double]]()
        for (lap,points) in result.laps.enumerated() {
            let hs:[Double]
            if lap==0 {hs=Array(repeating:first,count:path.count)}else if lap==turns+1 {hs=fractions.map{pitch*(1-$0)}}else if lap==1 {hs=fractions.map{pitch*$0}}else{hs=Array(repeating:pitch,count:path.count)}
            lapGaps.append((1..<points.count).map{(hs[$0-1]+hs[$0])/2})
            lapVolumes.append((1..<points.count).map{let lo=hs[$0-1],hi=hs[$0];return xyLength(points[$0-1],points[$0])*(width*(lo+hi)/2-edge*(lo*lo+lo*hi+hi*hi)/3)})
        }
        let description=String(format:"双螺旋花瓶走线 | 每侧 %g 圈 | 高 %.2f mm\n闭合轮廓：沿一侧绕入，圆弧回转后沿另一侧绕出。保留裙边与首层等高走线；墙体同向连续升 Z，不在端点往返换层。\n每完整一周实际上升 %.4f mm（不超过设置层高），共 %d 周；顶部按实际剩余间隙整平，不叠加末段 20%% 减流。\n本造型为无底灯罩，不生成整片实心底；不应用首层外缘校准。\nEF %.3f mm / %d 圈：首层沿闭合轮廓向内补偿，连续上升时逐圈恢复原尺寸。",p["DoubleTurns"],height,pitch,turns,p["EF"],Int(p["EFLayers"]))
        info.merge(["path":path,"layers":result.laps,"vase":true,"rise_turns":turns,"actual_pitch":pitch,"perimeter":perimeter,"fractions":fractions,"lap_gaps":lapGaps,"lap_volumes":lapVolumes]){_,new in new}
        return SliceShape(gcode:lines.joined(separator:"\n"),info:description,parameters:p,points:result.wall,wall:result.wall,sectionCount:1,details:["double":info])
    }
    static func doubleModel(_ values:SliceParameters) throws -> SliceShape {
        var p=values
        if p["DoubleLines"]==3 {return try doubleVaseModel(p)}
        let height=p["CH"],first=p["H0"],pitch=p["H"],width=p["W"],mode=p.values["DoubleLines"]==nil ? 1:p["DoubleLines"],profile=Int(p["DoubleProfile"])
        guard height>=first else {throw SliceFailure("双螺旋总高度不能小于首层层高。")}
        guard mode==1 || mode==2 else {throw SliceFailure("双螺旋走线方式须为单线或双线。")}
        let closed=mode==2,lane=p.values["DoubleLaneGap"]==nil ? 9:p["DoubleLaneGap"]
        var (path,info)=try closed ? returnOutline(p["DoubleD"],p["DoubleTurns"],p["DoubleGap"],width,lane,p["DoubleRot"],profile:profile):doubleOutline(p["DoubleD"],p["DoubleTurns"],p["DoubleGap"],width,p["DoubleRot"],profile:profile)
        let count=1+max(0,Int(ceil((height-first)/pitch-1e-9)))
        guard count*path.count<=220_000 else {throw SliceFailure("双螺旋路径超过 22 万段，请降低高度、减少圈数或增大层高。")}
        if closed && p.flag("AlignLeft") {path=alignedLoop(Array(path.dropLast()),true)}else if p.flag("AlignLeft") {let finalLeft=path[0].x<=path.last!.x,finalFirst=count%2==0;if finalLeft != finalFirst {path.reverse()}}
        let compensation=closed ? try ScrollCompensation(path,&p,(height-first)/pitch):nil,start=compensation?.at(0,time:0) ?? path[0]
        var lines=helicalHeader(p,kind:"DOUBLE_SCROLL",pitch:pitch,start:start,metadata:["; DOUBLE_TURNS_PER_SIDE="+fmt(p["DoubleTurns"]),"; DOUBLE_EDGE_GAP="+fmt(p["DoubleGap"]),"; DOUBLE_LINES=\(Int(mode))","; DOUBLE_CLOSED=\(closed ? 1:0)"],bottomHeight:pitch)
        lines.removeAll{$0.hasPrefix("; EF_") || $0=="; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH"};lines.insert(contentsOf:compensation?.metadata ?? ["; EF_AMOUNT=0"],at:lines.firstIndex(of:"; E_UNITS=VOLUME_MM3")!)
        var layers=[[SlicePoint]](),wall=[SlicePoint](),previousZ=0.0
        for layer in 0..<count {
            let z=min(height,first+Double(layer)*pitch),h=z-previousZ;previousZ=z
            let current=compensation?.at(Array(repeating:(z-first)/pitch,count:path.count)) ?? (layer%2==0 ? path:Array(path.reversed())),points=current.map{SlicePoint($0.x,$0.y,z)}
            try compensation?.checkLap(points,layers.last)
            if layer>0 {lines.append("G0 Z"+fmt(z)+" F600");if compensation != nil && (points[0].x != layers.last!.last!.x || points[0].y != layers.last!.last!.y) {lines.append("G0 X\(fmt(points[0].x)) Y\(fmt(points[0].y)) F3000")}}
            lines.append("; GH_WALL_TURN=\(layer)")
            for i in 1..<points.count {let b=points[i];lines += ["; GH_GAP_HEIGHT="+fmt(h),"G1 X\(fmt(b.x)) Y\(fmt(b.y)) Z\(fmt(z)) E\(fmt(xyLength(points[i-1],b)*beadArea(width,h))) F420"]}
            layers.append(points);wall += points
        }
        lines.append("; ===== PRINT PATH END =====")
        var description=String(format:"双螺旋 | 每侧 %g 圈 | 外缘间距 %.2f mm | 高 %.2f mm\n两侧镜像内卷，中间连续连接；逐层等高往返，端点抬 Z 换层。\n当前为开放卷曲墙体，不含整片底面或坐面；不应用 EF、首层外缘校准或三角波。\n自动收尾沿最后一段减流；造型预览尚未验证座具承重。",p["DoubleTurns"],p["DoubleGap"],height)
        if closed {description=String(format:"双螺旋双线 | 每侧 %g 圈 | 两瓣间距 %.2f mm | 双线净间隙 %.2f mm\n沿一侧绕入、中心圆弧回转，再沿另一侧绕出；两瓣连成一条闭合路径。\n每层等高走完闭合轮廓，在接缝抬 Z 换层；不含整片底面或坐面。\n首层外缘校准不参与；造型预览尚未验证座具承重。",p["DoubleTurns"],p["DoubleGap"],lane)}
        if (1...3).contains(profile) {
            lines.insert("; DOUBLE_PROFILE="+[1:"S_SCROLL_LAMP",2:"CIRCULAR_S_SCROLL",3:"FAIR_ARCHIMEDEAN_SCROLL"][profile]!,at:2)
            description=String(format:"S 形双卷长灯 | 灯体长度 %.2f mm | 每侧 %g 圈\n两瓣旋转对称，中央平滑连接；长度沿 Z 方向延伸，截面尺寸不变。\n打印时长轴竖直；单线逐层沿原路往返，双线沿闭合轮廓换层。\n仅生成卷曲灯罩，不含灯座、吊装连接或整片底面。",height,p["DoubleTurns"])
            if profile==2 {description+=String(format:"\n圆弧深卷：两侧各含 270° 正圆主弧，内卷与连接处曲率连续；两圆参考外缘间距 %.2f mm。",p["DoubleGap"])}
            if profile==3 {description+=String(format:"\n等距阿基米德双螺旋 + 欧拉过渡；每侧 %g 圈，参考间距 %.2f mm；修改间距后重新求解接入角度与过渡长度。",p["DoubleTurns"],p["DoubleGap"])}
        }
        if closed {description+=String(format:"\nEF %.3f mm / %d 圈：沿闭合轮廓向内补偿，逐层恢复原尺寸。",p["EF"],Int(p["EFLayers"]))}
        info["path"]=path;info["layers"]=layers
        return SliceShape(gcode:lines.joined(separator:"\n"),info:description,parameters:p,points:wall,wall:wall,sectionCount:1,details:["double":info])
    }
}
