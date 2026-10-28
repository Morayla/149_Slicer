import Foundation

extension SliceGeometry {
    static func cornerOutline(_ p:SliceParameters) throws -> ([SlicePoint],[String:Any]) {
        let side=p["CornerSide"],width=p["W"],gap=p["CornerLaneGap"],diameter=p["CornerPipeD"],clearance=p["CornerClearance"]
        guard (60...500).contains(side) else {throw SliceFailure("墙角占位边长需为 60–500 mm。")}
        guard (1...100).contains(diameter),(0...5).contains(clearance) else {throw SliceFailure("管外径需为 1–100 mm，直径装配余量需为 0–5 mm。")}
        guard (0.5...10).contains(gap) else {throw SliceFailure("双线净间隙需为 0.5–10 mm。")}
        let half=(width+gap)/2,pad=half+width/2,required=(diameter+clearance)/2,pr=required+0.03,pipe=SlicePoint(side-2*pad-pr,2*pad+pr,0),rr=pr+pad,radius=side/4,inner=max(6,half+1)
        guard inner<radius,half<10 else {throw SliceFailure("线宽与占位尺寸不匹配，请增大占位边长或减小线宽。")}
        func unit(_ q:SlicePoint)throws->SlicePoint {let d=hypot(q.x,q.y);guard d>=1e-10 else {throw SliceFailure("墙角轮廓存在退化切线，请调整尺寸。")};return q*(1/d)}
        func line(_ a:SlicePoint,_ b:SlicePoint,_ n:Int)->[SlicePoint] {(0..<n).map{let t=Double($0)/Double(n-1);return a*(1-t)+b*t}}
        func arc(_ center:SlicePoint,_ r:Double,_ a:Double,_ b:Double,_ n:Int)->[SlicePoint] {(0..<n).map{let t=a+(b-a)*Double($0)/Double(n-1);return center+SlicePoint(r*cos(t),r*sin(t),0)}}
        let center=SlicePoint(pipe.x-rr-radius,pipe.y,0)
        var lower=(0...600).map{i -> SlicePoint in let u=Double(i)/600,r=radius-(radius-inner)*pow(u,1.25),a=tau*u;return center+SlicePoint(r*cos(a),r*sin(a),0)}
        let shift=lower.map{$0.y}.min()!-pad;lower=Array(lower.map{SlicePoint($0.x,$0.y-shift,0)}.dropFirst(48))
        let q=lower[0],endpoint=pipe+SlicePoint(-rr,0,0),tangent=try unit(q-lower[1]),handle=xyLength(q,endpoint)*0.4,p1=q+tangent*handle,p2=endpoint+SlicePoint(0,handle,0)
        let link=(0..<80).map{i -> SlicePoint in let t=Double(i)/79;return pow(1-t,3)*q+3*pow(1-t,2)*t*p1+3*(1-t)*t*t*p2+pow(t,3)*endpoint}
        lower=Array(link.reversed())+lower.dropFirst()
        func mirror(_ q:SlicePoint)->SlicePoint {SlicePoint(side-q.y,side-q.x,0)}
        let upper=lower.map(mirror),tail=arc(pipe,rr,Double.pi,1.5*Double.pi,121),tailB=tail.reversed().map(mirror),bridge=arc(SlicePoint(side-pad-10,pad+10,0),10,-Double.pi/2,0,100)
        guard tail.last!.x<bridge[0].x else {throw SliceFailure("管径过小，无法容纳当前圆角与双线间距。")}
        var spine=Array(lower.reversed())+tail.dropFirst();spine += line(tail.last!,bridge[0],25).dropFirst();spine += bridge.dropFirst();spine += line(bridge.last!,tailB[0],25).dropFirst();spine += tailB.dropFirst();spine += upper.dropFirst()
        let tangents=try spine.indices.map{try unit(spine[min($0+1,spine.count-1)]-spine[max(0,$0-1)])},normals=tangents.map{SlicePoint(-$0.y,$0.x,0)}
        let left=zip(spine,normals).map{$0+half*$1},right=zip(spine,normals).map{$0-half*$1}
        var end=[SlicePoint](),start=[SlicePoint]()
        for i in 0..<48 {let a=Double.pi*Double(i)/47;end.append(spine.last!+half*(cos(a)*normals.last!+sin(a)*tangents.last!));start.append(spine[0]-half*(cos(a)*normals[0]+sin(a)*tangents[0]))}
        var poly=[SlicePoint]()
        for part in [left,end,Array(right.reversed()),start] {let points=simplify(part);poly += poly.isEmpty ? points:Array(points.dropFirst())}
        if xyLength(poly[0],poly.last!)<1e-8 {poly.removeLast()}
        let minimum=try checkSpacing(poly,width:width),bore=poly.indices.map{pointDistance(pipe,poly[$0],poly[($0+1)%poly.count])}.min()!-width/2
        guard bore>=required else {throw SliceFailure("当前尺寸无法保留指定管孔，请调整占位边长或线宽。")}
        let bounds=[poly.map{$0.x}.min()!-width/2,poly.map{$0.y}.min()!-width/2,poly.map{$0.x}.max()!+width/2,poly.map{$0.y}.max()!+width/2]
        guard min(bounds[0],bounds[1])>=(-0.02),max(bounds[2],bounds[3])<=side+0.02 else {throw SliceFailure("当前卷曲超出墙角边界，请调整占位边长、管径或线宽。")}
        poly=poly.map{SlicePoint($0.x-side/2,$0.y-side/2,0)}
        let info:[String:Any]=["pipe_center":[pipe.x-side/2,pipe.y-side/2],"pipe_diameter":diameter,"clearance":clearance,"requested_bore":2*required,"minimum_bore":2*bore,"minimum_spacing":minimum,"bounds":bounds,"side":side]
        return (alignedLoop(poly,p.flag("AlignLeft")),info)
    }
    static func cornerModel(_ p:SliceParameters) throws -> SliceShape {
        let first=p["H0"],height=p["CH"],nominal=p["H"]
        guard height>=first+nominal else {throw SliceFailure("模块高度需包含首层及至少一个完整墙体层高。")}
        var (path,info)=try cornerOutline(p)
        let fractions=pathFractions(path),turns=max(1,Int(ceil((height-first)/nominal-1e-9))),pitch=(height-first)/Double(turns)
        guard (path.count-1)*(turns+2)<=220_000 else {throw SliceFailure("墙角螺旋路径超过 22 万段，请降低模块高度或增大层高。")}
        let minimum=info["minimum_bore"] as! Double
        var lines=helicalHeader(p,kind:"CORNER_PIPE",pitch:pitch,start:path[0],metadata:["; CORNER_PIPE_VASE=1","; CORNER_PIPE_DIAMETER="+fmt(p["CornerPipeD"]),"; CORNER_PIPE_BORE_MIN="+fmt(minimum),"; CORNER_PIPE_CLEARANCE_DIAMETRAL="+fmt(p["CornerClearance"])])
        let result=try helicalPath(p,fractions:fractions,marker:"CORNER_PIPE",lines:&lines,at:{i,z in SlicePoint(path[i].x,path[i].y,z)})
        let description=String(format:"墙角双卷 · 连接管 | 占位 %g × %g mm | 高 %g mm\n管外径 Ø%g mm；直径装配余量 %g mm（单边 %g mm）；预留通孔 Ø%g mm。\n截面含线宽后的最小通孔 %.3f mm，贯穿全高；钢管不打印。\n双线闭合，首层等高，墙体连续升 Z；%d 周，实际层高 %.4f mm。无底面，不应用 EF 或首层外缘校准。\n保留右侧与底侧墙面相切关系。实际插配请先打印短段试装。",p["CornerSide"],p["CornerSide"],height,p["CornerPipeD"],p["CornerClearance"],p["CornerClearance"]/2,p["CornerPipeD"]+p["CornerClearance"],minimum,turns,pitch)
        info["path"]=path;info["actual_pitch"]=pitch;info["rise_turns"]=turns
        return SliceShape(gcode:lines.joined(separator:"\n"),info:description,parameters:p,points:result.wall,wall:result.wall,sectionCount:1,details:["corner":info])
    }
}
