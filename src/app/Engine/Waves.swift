import Foundation

extension SliceGeometry {
    static func applyWaves(_ model:SliceShape,_ raw:SliceParameters) throws -> SliceShape {
        let p=model.parameters,mode=p.text("SourceMode")
        guard let cfg=try waveSettings(raw,mode:mode) else {return model}
        let blocked=["DoubleScroll":"双螺旋使用逐层往返走线","TripleVase":"三螺旋花瓶已配套扩容走线","NonplanarCylinder":"起伏口沿已配套非平面走线","Imported":"导入模型暂不支持三角波"]
        if let reason=blocked[mode] {throw SliceFailure(reason+"，请关闭三角波后切片。")}
        let wall=model.wall,baseZ=wall[0].z,pitch=p["H"],aligned=p.flag("AlignLeft"),total=turns(p["CH"],baseZ,pitch,aligned),count=Int(ceil(total)),n=cfg.count
        let modes=(0..<count).map{$0<cfg.start ? 0:cfg.pattern[($0-cfg.start)%cfg.pattern.count]},phases=modes.map{$0==2 ? 0.5/n:0}
        if !modes.contains(where:{$0 != 0}) || cfg.amplitude==0 && cfg.negative==0 {return model}
        guard Double(count)*max(1200,n*120)<=5_000_000 else {throw SliceFailure("波形计算过密，请减少高度或波数。")}
        let triple=mode=="Triple",ellipse=mode=="Ellipse",global=n != n.rounded(.towardZero)
        guard !ellipse || global || Set(cfg.pattern).count<=1 else {throw SliceFailure("椭圆交错波请开启「自动匹配波数」并使用 1,2 交替；也可重复同一种波形。")}
        guard !global || !triple else {throw SliceFailure("半整数连续交错波暂支持圆柱和锥体；三螺旋请使用整数波数。")}
        let section:WaveSection,normal:(SlicePoint,Double,Double)throws->SIMD2<Double>,pointAt:((Double,Double)throws->SlicePoint)?
        if triple {
            let outline=(model.details["outline"] as! TripleOutline).points,path=Polyline(outline),orientation=area(outline)>0 ? 1.0:-1.0,seam=model.details["seam"] as? Double ?? 0.135
            section={turn,u in path.at(seam+u,z:turnZ(turn,p["CH"],baseZ,pitch,aligned))}
            normal={_,_,u in let a=path.at(seam+u-1e-5),b=path.at(seam+u+1e-5),dx=b.x-a.x,dy=b.y-a.y,d=hypot(dx,dy);guard d>=1e-9 else {throw SliceFailure("三螺旋局部法线不明确。")};return SIMD2(orientation*dy/d,-orientation*dx/d)};pointAt=nil
        }else if ellipse {
            guard p["W"]/2+p["EF"]+cfg.negative<pow(p["EllipseMinor"],2)/(2*p["EllipseMajor"]) else {throw SliceFailure("椭圆波谷内凹过大，端部可能重叠；请减小内凹或增大短轴。")}
            var ep=p;let ef=try efProfile(&ep),angle=atan2(wall[0].y,wall[0].x);var paths=[Double:Polyline]()
            let ellipseSection:WaveSection={turn,u in
                let z=turnZ(turn,p["CH"],baseZ,pitch,aligned)
                if paths[turn]==nil {
                    let contour=try inward(.polygon(model.source!.loop(z),z),p["W"]/2+p["EF"]*ef(turn),z,p)
                    guard case .polygon(let poly,_)=contour else {throw SliceFailure("Missing ellipse")}
                    let points=sampledPolygon(poly,z:0,count:max(256,poly.count*2),angle:angle);paths[turn]=Polyline(points+[points[0]])
                }
                return paths[turn]!.at(u,z:z)
            }
            section=ellipseSection
            pointAt={progress,displacement in
                let j=max(0,floor(progress)),t=progress-j
                func at(_ u:Double) throws -> SlicePoint {let a=try ellipseSection(j,u),b=try ellipseSection(j+1,u);return a+(b-a)*t}
                let q=try at(progress),a=try at(progress-1e-4),b=try at(progress+1e-4),dx=b.x-a.x,dy=b.y-a.y,d=hypot(dx,dy)
                guard d>=1e-9 else {throw SliceFailure("椭圆波形法线无效，请调整尺寸。")};return SlicePoint(q.x+displacement*dy/d,q.y-displacement*dx/d,q.z)
            }
            normal={_,_,_ in .zero}
        }else{
            var ep=p;let ef=try efProfile(&ep),angle=atan2(wall[0].y,wall[0].x)
            section={turn,u in
                let z=turnZ(turn,p["CH"],baseZ,pitch,aligned),r=try loopAt(nil,z,p).radius-p["W"]/2-p["EF"]*ef(turn)
                guard r>cfg.negative+p["W"]/2 else {throw SliceFailure("波谷内凹过大，已接近或穿过模型中心。")};let a=angle+u*tau;return SlicePoint(r*cos(a),r*sin(a),z)
            }
            normal={q,_,_ in let d=hypot(q.x,q.y);guard d>=1e-9 else {throw SliceFailure("波形相位使路径穿过中心，请增加波数。")};return SIMD2(q.x/d,q.y/d)};pointAt=nil
        }
        let previous=try (0...1200).map{try section(0,Double($0)/1200)}
        var history=[(previous,(0...1200).map{-1+Double($0)/1200})],allPoints=[wall[0]],moves=[String](),maxUnsupported=0.0,lastProgress=0.0
        for layer in modes.indices {
            let index=WaveSupportIndex(width:p["W"]);for item in history.suffix(2) {index.extend(item.0,item.1)}
            let mode=modes[layer],phase=phases[layer],fraction=min(1,total-Double(layer));if fraction<=0 {break}
            func atPhase(_ t:Double,_ offset:Double) throws -> SlicePoint {let a=try section(Double(layer),t+offset),b=try section(Double(layer+1),t+offset);return a+(b-a)*t}
            func base(_ t:Double) throws -> SlicePoint {try atPhase(t,phase)}
            func norm(_ q:SlicePoint,_ t:Double) throws -> SIMD2<Double> {try normal(q,t,t+phase)}
            var vertices:[WaveVertex]
            if mode != 0 && !triple {
                if global || ellipse {vertices=try globalWaveVertices(section,layer:layer,start:cfg.start,total:total,n:n,firstMode:cfg.pattern[0],amplitude:cfg.amplitude,negative:cfg.negative,source:cfg.source,fraction:fraction,pointAt:pointAt,heightAt:ellipse ? {turnZ($0,p["CH"],baseZ,pitch,aligned)}:nil)}
                else {vertices=try circularWaveVertices(section,layer,mode,n,cfg.amplitude,cfg.negative,cfg.source,fraction)}
                vertices[0]=WaveVertex(0,allPoints.last!)
                if fraction==1 && layer+1<count && modes[layer+1]==0 {vertices[vertices.count-1]=WaveVertex(1,try section(Double(layer+1),1))}
                if layer==0 && cfg.source,let raised=vertices.firstIndex(where:{$0.point.z>baseZ+1e-10}),raised>1 {let t1=vertices[raised].t,q1=vertices[raised].point;for i in 1..<raised {vertices[i].point.z=baseZ+(q1.z-baseZ)*vertices[i].t/t1}}
            }else if mode != 0 {
                vertices=try triangleVertices(base,norm,Int(n),cfg.amplitude,cfg.negative,cfg.source,arcLength:triple)
                for i in 1..<vertices.count {
                    let ta=vertices[i-1].t,tb=vertices[i].t,a=try base(ta),b=try base(tb),c=try base((ta+tb)/2)
                    guard hypot(c.x-(a.x+b.x)/2,c.y-(a.y+b.y)/2)<=p["W"]/2 else {throw SliceFailure("三螺旋的波数太少，三角直边会跨过盘绕路径；请增加「每遍波数」后重试。")}
                }
                vertices=try vertices.map {v in
                    let t=v.t,q=v.point,offset=seamPhase(t,phase,n);if abs(offset-phase)<1e-14 {return v}
                    let a=try base(t),direction=try norm(a,t),displacement=(q.x-a.x)*direction.x+(q.y-a.y)*direction.y,b=try atPhase(t,offset),newNormal=try normal(b,t,t+offset)
                    return WaveVertex(t,SlicePoint(b.x+displacement*newNormal.x,b.y+displacement*newNormal.y,q.z))
                }
            }else{
                let samples=try max(128,Int(ceil(n*12)),Int(ceil(xyLength(base(0),base(0.001))*1000/1.5)))
                vertices=try (0...samples).map{let t=Double($0)/Double(samples);return WaveVertex(t,try base(t))}
            }
            if mode==0 || triple {vertices=try connectVertices(vertices,allPoints.last!,section(Double(layer+1),1),fraction,n,mode != 0 && cfg.source)}
            let dense=densify(vertices);var current=[allPoints.last!],currentProgress=[lastProgress]
            for v in dense.dropFirst() {
                let t=v.t,q=v.point,progress=Double(layer)+t+(triple ? seamPhase(t,phase,n):0),a=allPoints.last!
                if distance3(a,q)<1e-9 {continue}
                guard q.z>=a.z-1e-6 else {throw SliceFailure("波形产生向下打印的连接，请调整排列或波数。")}
                let mid=(a+q)/2,(under,distance)=index.height(mid,fallback:mid.z-pitch,progress:(lastProgress+progress)/2),gap=max(0.000001,mid.z-under)
                maxUnsupported=max(maxUnsupported,distance.isFinite ? distance:p["W"]*3)
                guard gap<=p["W"] else {throw SliceFailure("波形的局部挤出间隙超过线宽，请增加波数或减小层高。")}
                let e=xyLength(a,q)*beadArea(p["W"],gap)
                moves += ["; GH_GAP_HEIGHT="+fmt(gap),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(e)) F420"]
                index.add(a,q,(lastProgress,progress));allPoints.append(q);current.append(q);currentProgress.append(progress);lastProgress=progress
            }
            guard allPoints.count<=180_000 else {throw SliceFailure("波形路径超过 18 万段，请减少高度或波数。")}
            history=Array((history+[(current,currentProgress)]).suffix(2))
        }
        let lines=SliceGcode.lines(model.gcode)
        guard let first=try SliceGcode.records(model.gcode).0.first(where:{$0.extrusion != nil && ($0.after.z ?? 0)>baseZ+1e-7 && $0.section=="WALL"})?.line else {throw SliceFailure("Missing rising wall")}
        let cut=lines[first-1].hasPrefix("; GH_GAP_HEIGHT=") ? first-1:first
        var text=(Array(lines[..<cut])+["; WAVE_PROCESS_BEGIN"]+moves+["; WAVE_PROCESS_END","; ===== PRINT PATH END ====="]).filter{!$0.hasPrefix("; G1_FINISH_CANDIDATE=")}.joined(separator:"\n")
        let top=allPoints.last!.z
        for (key,value) in [("TOTAL_HEIGHT",fmt(top)),("WAVE_Z_MODE",cfg.source ? "Source":"Continuous"),("WAVE_PHASE_MODE",ellipse ? "GLOBAL_ARCLENGTH":global ? "GLOBAL_HALF_WAVE":triple ? "FIXED_AB_LOCAL_SEAM":"FIXED_AB_EDGE_CROSSING"),("WAVE_COUNT",fmt(n)),("WAVE_SEAM_MODE","CONTINUOUS_XYZ")] {text=SliceGcode.setMeta(text,key,value)}
        var output=model;output.gcode=text;output.wall=allPoints;output.details["wave_points"]=allPoints;output.parameters["CH"]=top;output.details["wave_fit"]=cfg.fit;output.details["wave_max_lateral"]=maxUnsupported
        output.info="三角波：外凸 \(fmt(cfg.amplitude)) / 内凹 \(fmt(cfg.negative)) mm，\(fmt(n)) 波/遍；排列 \(cfg.pattern.map(String.init).joined(separator:","))；\(cfg.source ? "原脚本局部等高":"连续上升")。"
        if let fit=cfg.fit {output.info+="\n波数校核：\(fmt(fit["requested"] as! Double)) → \(fmt(n)) 波/遍。";if fit["kind"] as? String=="transitions" {output.info+=" 当前排列包含模式切换，过渡处不能保证等距。"}}
        if global {output.info+="\n半整数波数沿整条路径连续延续，每圈自然错开半波；起始接入与最终截断除外。"}
        if maxUnsupported>p["W"]/2 {output.info+=" 波形有较大横向悬伸，需实机验证。"}
        output.info+="\n"+model.info;return output
    }
}
