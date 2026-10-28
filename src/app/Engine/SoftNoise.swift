import Foundation

extension SliceGeometry {
    static func applyNoise(_ model:SliceShape,_ raw:SliceParameters) throws -> SliceShape {
        if !raw.flag("NoiseEnabled") {return model}
        let p=model.parameters
        guard ["Cylinder","Cone"].contains(p.text("SourceMode")) else {throw SliceFailure("柔和随机波目前支持圆柱与圆台造型。")}
        guard !raw.flag("WaveEnabled"),!raw.flag("MeshEnabled") else {throw SliceFailure("柔和随机波不能与三角波、波浪网孔同时启用。")}
        guard ["NoiseAmplitude","NoiseScale","NoiseVariation","NoiseSeed"].allSatisfy({raw[$0].isFinite}) else {throw SliceFailure("随机波参数必须是有限数值。")}
        let amp=raw["NoiseAmplitude"],scale=raw["NoiseScale"],variation=raw["NoiseVariation"],seed=raw["NoiseSeed"]
        guard amp>=0,scale>0,(0...100).contains(variation),seed.rounded(.towardZero)==seed,(0...2147483647).contains(seed) else {throw SliceFailure("幅度须非负，尺度须为正；层间变化为 0–100%，种子为 0–2147483647 的整数。")}
        let zRequested=raw.flag("NoiseZEnabled") ? (raw.values["NoiseZAmplitude"]==nil ? 0.2:raw["NoiseZAmplitude"]):0,strength=raw.values["NoiseStrength"]==nil ? 1:raw["NoiseStrength"]
        guard zRequested.isFinite,zRequested>=0 else {throw SliceFailure("垂直起伏幅度必须为非负有限数值。")}
        guard strength.isFinite,(1...3).contains(strength) else {throw SliceFailure("纹理强度须为 1–3 倍。")}
        if amp==0 && zRequested==0 {return model}
        func contrast(_ value:Double)->Double {let c=strength-1;return c<1e-8 ? value:tanh(c*value)/tanh(c)}
        let slopeGain=strength<=1 ? 1:(strength-1)/tanh(strength-1),wall=model.wall,base=wall[0].z,zs=wall.map{$0.z},angles=wall.map{atan2($0.y,$0.x)}
        let deltas=(1..<angles.count).map{modulo(angles[$0]-angles[$0-1],tau)}.filter{$0>1e-8 && $0<0.2}.sorted()
        guard !deltas.isEmpty else {throw SliceFailure("圆柱采样不足，无法生成柔和随机波。")}
        let median=deltas.count%2==1 ? deltas[deltas.count/2]:(deltas[deltas.count/2-1]+deltas[deltas.count/2])/2,n=max(16,Int((tau/median).rounded(.toNearestOrEven)))
        let original=wall.count>n ? (n..<wall.count).map{xyLength(wall[$0-n],wall[$0])}.max()!:0,limit=(p["W"]-p["H"]*edge)/2+p["Tolerance"],effective=min(amp,p["W"]*0.2,max(0,(limit-original)/2))
        guard amp<=0 || effective>=1e-5 else {throw SliceFailure("当前 EF 或接入偏移已占满层间搭接余量，请减小 EF 后使用随机波。")}
        let circumference=tau*wall.map{hypot($0.x,$0.y)}.max()!,initialScale=max(scale,2*p["W"],circumference/Double(max(2,n/24))),target=max(2,min(80,circumference/initialScale)),actualScale=circumference/target
        let low=max(2,Int((target*0.65).rounded(.toNearestOrEven))),high=max(low,min(n/16,Int((target*1.35).rounded(.toNearestOrEven)))),harmonics=Array(low...high),weights=harmonics.map{exp(-pow((Double($0)-target)/max(1,target*0.35),2))},total=weights.reduce(0,+),turns=Double(wall.count-1)/Double(n)
        let pitches=wall.count>n ? (n..<wall.count).map{wall[$0].z-wall[$0-n].z}:[],minPitch=pitches.min() ?? max(0.000001,zs.last!-base),zAmp=min(zRequested,0.1*minPitch,0.12*circumference/(tau*Double(high)*slopeGain))
        struct Key:Hashable {let knot:Int;let channel:Int};var cache=[Key:[Double]]()
        func phases(_ knot:Int,_ channel:Int=0)->[Double] {
            let key=Key(knot:knot,channel:channel);if let found=cache[key] {return found}
            var rng=TextureRandom(seed:UInt64(seed)*1000003+UInt64(knot)*9176+UInt64(channel)*2147483647)
            let values=harmonics.map{_ in tau*rng.uniform()};cache[key]=values;return values
        }
        func progress(_ z:Double)->Double {
            let j=lowerBound(zs,z);if j<=0 {return 0};if j>=zs.count {return Double(zs.count-1)/Double(n)}
            let lo=zs[j-1],hi=zs[j];return hi>lo ? (Double(j-1)+(z-lo)/(hi-lo))/Double(n):Double(j)/Double(n)
        }
        func texture(_ angle:Double,_ t:Double,_ channel:Int)->Double {
            let v=t*variation/100,knot=Int(floor(v)),blend=smooth(v-Double(knot)),a=phases(knot,channel),b=phases(knot+1,channel)
            var value=0.0
            for i in harmonics.indices {let k=Double(harmonics[i]);value+=weights[i]*((1-blend)*cos(k*angle+a[i])+blend*cos(k*angle+b[i]))}
            return contrast(value/total)
        }
        func zShift(_ angle:Double,_ t:Double)->Double {if zAmp==0 || t<=0 || t>=turns {return 0};return zAmp*smooth(t)*smooth(turns-t)*texture(angle,t,1)}
        func moved(_ q:SlicePoint) throws -> SlicePoint {
            if q.z<=base {return q}
            let r=hypot(q.x,q.y),angle=atan2(q.y,q.x),t=progress(q.z),d=effective*smooth(t)*texture(angle,t,0)
            guard r+d>p["W"]/2 else {throw SliceFailure("随机波内缩过大，请增大圆柱直径。")}
            return SlicePoint(q.x*(r+d)/r,q.y*(r+d)/r,q.z+zShift(angle,t))
        }
        let newWall=try wall.map(moved)
        if newWall.count>n && (n..<newWall.count).contains(where:{xyLength(newWall[$0-n],newWall[$0])>limit+1e-6}) {throw SliceFailure("随机波层间偏移超过搭接范围，请减小幅度或 EF。")}
        var lines=SliceGcode.lines(model.gcode),lastTurn:Int?
        for record in try SliceGcode.records(model.gcode).0 {
            guard record.section=="WALL",let extrusion=record.extrusion,record.distance>0,let a=record.before.point,let b=record.after.point,b.z>base else {continue}
            let aa=try moved(a),bb=try moved(b),index=record.line
            var line=SliceGcode.word(SliceGcode.word(lines[index],"X",bb.x),"Y",bb.y)
            if zAmp>0 {
                let t=progress(b.z),angle=atan2(b.y,b.x),oldGap=Double(lines[index-1].components(separatedBy:"=")[1])!,gap=oldGap+zShift(angle,t)-zShift(angle,t-1)
                guard gap>0,gap<=p["W"] else {throw SliceFailure("垂直起伏后的局部层高无效，请减小幅度或层高。")}
                let ratio=beadArea(p["W"],gap)/beadArea(p["W"],oldGap)
                line=SliceGcode.word(SliceGcode.word(line,"Z",bb.z),"E",extrusion*distance3(aa,bb)/record.distance*ratio)
                let turn=max(0,Int(floor(t-1e-5))),marker=turn != lastTurn ? "; GH_WALL_TURN=\(turn)\n":"";lastTurn=turn
                lines[index-1]=marker+"; GH_GAP_HEIGHT="+fmt(gap);lines[index]=line
            }else{lines[index]=SliceGcode.word(line,"E",extrusion*xyLength(aa,bb)/record.distance)}
        }
        for i in lines.indices where lines[i].hasPrefix("; G1_FINISH_CANDIDATE=") {
            let text=String(lines[i].dropFirst("; G1_FINISH_CANDIDATE=".count));var candidate=try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Any]
            let points=try (candidate["points"] as! [[Double]]).map{try moved(SlicePoint($0[0],$0[1],$0[2]))};candidate["points"]=coordinates(points)
            if zAmp>0 {
                var factors=[Double]()
                for j in 1..<points.count {
                    let a=points[j-1],b=points[j],t=turns-1+(Double(j)-0.5)/Double(points.count-1),index=max(0,min(Double(zs.count-1),t*Double(n))),lo=min(zs.count-2,Int(index)),u=index-Double(lo),below=zs[lo]*(1-u)+zs[lo+1]*u,angle=atan2(a.y+b.y,a.x+b.x),gap=zs.last!-below,corrected=gap-zShift(angle,t)
                    guard gap>0,corrected>0 else {throw SliceFailure("随机波收尾与下方料道间隙无效，请减小垂直幅度。")}
                    factors.append(beadArea(p["W"],corrected)/beadArea(p["W"],gap))
                }
                candidate["flow_factors"]=factors
            }
            lines[i]="; G1_FINISH_CANDIDATE="+(try json(candidate))
        }
        if zAmp>0 {lines.insert("; NONPLANAR_MODE=SOFT_NOISE_Z_V1",at:1)}
        lines.insert("; SOFT_NOISE_SEED=\(Int(seed)) AMPLITUDE=\(fmt(effective)) SCALE=\(fmt(actualScale))",at:1)
        var output=model;output.gcode=lines.joined(separator:"\n");output.wall=newWall;output.details["wallPath"]=try ((model.details["wallPath"] as? [SlicePoint]) ?? model.wall).map(moved);output.points=try model.points.map{try $0.z>base ? moved($0):$0}
        output.details["noise_fit"]=["requested":amp,"effective":effective,"scale":actualScale,"z_requested":zRequested,"z_effective":zAmp,"strength":strength]
        output.info=String(format:"柔和随机波：幅度上限 %g → %.3f mm，波纹尺度约 %.2f mm，层间变化 %g%%，种子 %d。\n只改变墙体 XY，Z 和规划层高不变；首圈渐入，角向周期闭合。挤出按实际 XY 长度重新计算。\n幅度按线宽和原 EF 偏移限制，保留上下圈搭接；预览不模拟材料变形。\n",amp,effective,actualScale,variation,Int(seed))+model.info
        if zAmp>0 {output.info=String(format:"垂直微起伏：幅度上限 %g → %.3f mm；首尾渐变，底部不变。局部间距与三维路径长度共同决定挤出量；自动收尾沿顶部纹理整圈减流，并补偿下方 Z 起伏。\n几何估算不模拟材料流动和喷嘴外形。\n",zRequested,zAmp)+output.info.replacingOccurrences(of:"只改变墙体 XY，Z 和规划层高不变；首圈渐入，角向周期闭合。挤出按实际 XY 长度重新计算。",with:"XY 与 Z 平滑起伏，角向周期闭合；局部层高随相邻圈的高度差变化。")}
        output.info=String(format:"纹理强度 %g 倍；保留造型尺寸参数，局部外缘随起伏变化。\n",strength)+output.info;return output
    }
}
