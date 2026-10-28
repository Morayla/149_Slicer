import Foundation

extension SliceGeometry {
    enum Contour {
        case circle(Double,Double)
        case polygon([SlicePoint],Double)
        var radius:Double {switch self {case .circle(let r,_):return r;case .polygon(let p,_):return p.map{hypot($0.x,$0.y)}.max() ?? 0}}
    }
    static func bottleRadius(_ z:Double,_ p:SliceParameters)->Double {
        let radius=p["BottleDiameter"]/2,neck=p["BottleBore"]/2+p["W"],h=p["BottleShoulder"],ease=min(10,h/4)
        let t=min(h,max(0,z-p["BottleBody"]))
        let s=t<ease ? t*t/(2*ease):(t>h-ease ? h-ease-pow(h-t,2)/(2*ease):t-ease/2)
        return radius+(neck-radius)*s/(h-ease)
    }
    static func hopperLowerRadius(_ t:Double)->Double {
        if t>=180.7 {return 32+4*(t-180.7)/14}
        let q=min(160,max(0,t)),s=q<10 ? q*q/20:(q>150 ? 150-pow(160-q,2)/20:q-5)
        return 105-73*s/150
    }
    static func loopAt(_ source:SliceSections?,_ z:Double,_ p:SliceParameters) throws -> Contour {
        switch p.text("SourceMode") {
        case "Hopper":return .circle(hopperLowerRadius(z-(p["HopperHeight"]-194.7)),z)
        case "PelletBottle":return .circle(bottleRadius(z,p),z)
        case "Cone":
            let base=p.flag("HasBottom") ? p["H0"]+(p["B"]-1)*p["BH"]:p["H0"]
            let fraction=min(1,max(0,(z-base)/(p["CH"]-base)))
            return .circle((p["Dout"]+(p["ConeTopD"]-p["Dout"])*fraction)/2,z)
        default:if let source=source {return .polygon(try source.loop(z),z)};return .circle(p["Dout"]/2,z)
        }
    }
    static func inward(_ contour:Contour,_ distance:Double,_ z:Double,_ p:SliceParameters) throws -> Contour {
        switch contour {
        case .polygon(let points,_):return .polygon(try offset(points,distance),z)
        case .circle(let radius,_):
            guard radius-distance>max(p["Tolerance"],0.01) else {throw SliceFailure("线宽或 EF 过大，圆柱内缩后半径已不足。")}
            return .circle(radius-distance,z)
        }
    }
    static func sampled(_ contour:Contour,_ n:Int,seam:SlicePoint?=nil,angle:Double=0)->[SlicePoint] {
        switch contour {
        case .polygon(let points,let z):return sampledPolygon(points,z:z,count:n,angle:angle)
        case .circle(let radius,let z):
            let phase=seam.map{atan2($0.y,$0.x)} ?? angle
            return (0..<n).map {i in let a=phase+tau*Double(i)/Double(n);return SlicePoint(radius*cos(a),radius*sin(a),z)}
        }
    }
    static func radialBoundary(_ contour:Contour,_ n:Int,_ angle:Double,_ p:SliceParameters) throws -> [Double] {
        guard case .polygon(let poly,_)=contour else {return Array(repeating:contour.radius,count:n)}
        guard contains(poly,.zero) else {throw SliceFailure("螺旋底部要求中心位于轮廓内部；请选择 Monotonic 填充。")}
        var result=[Double]()
        for i in 0..<n {
            let dx=cos(angle+tau*Double(i)/Double(n)),dy=sin(angle+tau*Double(i)/Double(n));var hits=[Double]()
            for j in poly.indices {
                let a=poly[j],b=poly[(j+1)%poly.count],vx=b.x-a.x,vy=b.y-a.y,den=dx*vy-dy*vx
                if abs(den)<1e-10 {continue}
                let t=(a.x*vy-a.y*vx)/den,u=(a.x*dy-a.y*dx)/den
                if t>0 && u>=0 && u<1 {hits.append(t)}
            }
            guard let high=hits.max(),let low=hits.min(),high-low<=p["Tolerance"] else {throw SliceFailure("凹轮廓不适合中心螺旋填充，请选择 Monotonic。")}
            result.append(high)
        }
        return result
    }

    static func circularModel(_ values:SliceParameters,source supplied:SliceSections?=nil,stepHelper:URL?=nil) throws -> SliceShape {
        var p=try validate(values)
        let ef=try efProfile(&p)
        let source:SliceSections?
        if let supplied=supplied {source=supplied}
        else if p.text("SourceMode")=="Ellipse" {source=try EllipseSliceSections(p)}
        else if p.text("SourceMode")=="Imported" {
            source=try ImportedSliceSections(SliceMeshImport.triangles(file:p.text("ImportFile"),scale:p["ImportScale"],tolerance:p["Tolerance"],stepHelper:stepHelper),pitch:p["H"])
        } else {source=nil}
        let height=source?.height ?? p["CH"];p["CH"]=height
        let base=p.flag("HasBottom") ? p["H0"]+(p["B"]-1)*p["BH"]:p["H0"]
        let nominal=(height-base)/p["H"],closed=p.flag("AlignLeft") || p.text("SourceMode")=="NonplanarCylinder"
        let turns=turns(height,base,p["H"],closed)
        guard turns>=1 else {throw SliceFailure("Height must include base plus one complete wall turn")}
        if p["EF"]>0 && nominal<p["EFLayers"] {throw SliceFailure("Model height does not contain EFLayers complete wall turns")}
        let angle=p.flag("AlignLeft") ? Double.pi:modulo(p["SeamAngle"],360)*Double.pi/180
        let baseCurve=try loopAt(source,base,p)
        let samplingRadius=source?.radius ?? (p.text("SourceMode")=="Cone" ? max(baseCurve.radius,p["ConeTopD"]/2):baseCurve.radius)
        let filament=p.flag("_FilamentMode"),pointLimit=filament ? 250_000:(p.text("SourceMode")=="Hopper" ? 150_000:100_000)
        var n=p["N"] != 0 ? Int(p["N"]):max(128,Int(ceil(tau*samplingRadius/min(p["W"]/6,1.5))))
        if filament && p["N"]==0 {n=max(128,Int(ceil(tau*samplingRadius/min(3,sqrt(8*max(samplingRadius,0.1)*p["Tolerance"])))))}
        n=max(n,Int(ceil(24*360/p["BlendAngle"])))
        guard n<=2000,turns*Double(n)<=Double(pointLimit) else {throw SliceFailure("Too many path points; lower N or model height")}
        var bottoms=[[SlicePoint]](),volumes=[[Double?]](),gaps=[[Double]](),notes=[String]()
        if p.flag("HasBottom") && (p.text("BottomKind")=="Solid" || p.text("BottomPattern")=="Monotonic" || source != nil) {
            (bottoms,volumes,gaps)=try buildBottom(p,source,n,angle)
        } else if p.flag("HasBottom") {
            let boundary=try inward(loopAt(source,p["H0"],p),p["WB"]/2+p["EF"],p["H0"],p)
            let inner=(p["Din"]+p["WB"])/2
            let radii=source==nil ? Array(repeating:(p["Dout"]-p["WB"])/2-p["EF"],count:n):try radialBoundary(boundary,n,angle,p)
            guard radii.min()!>=inner+p["Tolerance"] else {throw SliceFailure("Hole and inward outer boundary leave no room for bottom spiral")}
            if p["B"]>1 && source != nil {
                let upper=try radialBoundary(inward(loopAt(source,base,p),p["WB"]/2+p["EF"],base,p),n,angle,p)
                if zip(radii,upper).map({abs($0-$1)}).max()!>p["Tolerance"] {throw SliceFailure("Multiple bottom layers require constant footprint; use B=1 or no bottom")}
            }
            let outer=radii.max()!,span=outer-inner,entry=p.flag("InnerOpen") && p.flag("InnerEntry")
            if p.flag("InnerOpen") && p["B"] != 1 {throw SliceFailure("InnerOpen requires one bottom layer")}
            if entry && !(p["H0"]...p["WB"]).contains(p["InnerStartW"]) {throw SliceFailure("InnerStartW must be H0..bottom width")}
            var entryParameters=p;entryParameters["W"]=p["WB"]
            let profile=try radialProfile(inner:inner,outer:outer,pitch:p["WB"]-max(p["H0"],p["BH"])*edge,ease:p["BlendAngle"]/360,open:p.flag("InnerOpen"),entry:entry ? entryParameters:nil)
            let steps=Int((profile.total*Double(n)).rounded(.toNearestOrEven))
            guard Double(steps)*p["B"]+turns*Double(n)<=Double(pointLimit) else {throw SliceFailure("More than 100000 points; reduce sampling or dimensions")}
            var ledgers=Array(repeating:[Ribbon](),count:n)
            for layer in 0..<Int(p["B"]) {
                let outward=(Int(p["B"])-1-layer)%2==0,z=p["H0"]+Double(layer)*p["BH"],lh=layer==0 ? p["H0"]:p["BH"]
                var pts=[SlicePoint](),rr=[Double](),es=[Double?](),hs=[Double]()
                for i in 0...steps {
                    let t=Double(i)/Double(n),value=profile.radius(t)
                    let r=inner+((outward ? value:inner+outer-value)-inner)/span*(radii[i%n]-inner),a=angle+tau*modulo(t,1)
                    pts.append(SlicePoint(r*cos(a),r*sin(a),z));rr.append(r)
                }
                for i in 0..<steps {
                    let r=(rr[i]+rr[i+1])/2,t=(Double(i)+0.5)/Double(n),width=profile.width?(t) ?? p["WB"]
                    var radialWidth=width-lh*edge
                    if source != nil {radialWidth*=sqrt(1+pow((rr[i+1]-rr[i])/(max(r,1e-6)*tau/Double(n)),2))}
                    let (e,gap)=paintRibbon(&ledgers[i%n],low:r-radialWidth/2,high:r+radialWidth/2,top:z,angleStep:tau/Double(n))
                    es.append(e);hs.append(gap)
                }
                bottoms.append(pts);volumes.append(es);gaps.append(hs)
            }
        } else {notes.append("无底：先打印一整圈平面墙脚，再连续螺旋上升。")}
        let eligible=edgeEligible(p)
        var edgeReport:EdgeReport?
        if p.flag("EdgeCalibrationEnabled") {
            if eligible {
                let corrected=try correctEdge(bottoms[0],volumes[0],gaps[0],n,p)
                bottoms[0]=corrected.0;volumes[0]=corrected.1;edgeReport=corrected.2
                notes.append(String(format:"首层外缘校准：EF 后叠加，最大内收 %.3f mm / 外补 %.3f mm；按原始流量识别外缘料道。",abs(corrected.2.min),corrected.2.max))
            } else {notes.append("首层外缘校准未应用：仅支持 G1、单层环形螺旋底、圆柱或锥形、左侧接缝。")}
        }
        guard Double(bottoms.reduce(0){$0+$1.count})+turns*Double(n)<=Double(pointLimit) else {throw SliceFailure("More than 100000 points; reduce sampling or dimensions")}
        var cache=[Double:[SlicePoint]](),sectionCount=0
        func section(_ t:Double,_ ref:SlicePoint?=nil) throws -> [SlicePoint] {
            let key=(t*1e9).rounded(.toNearestOrEven)/1e9
            if let old=cache[key] {return old}
            let z=turnZ(t,height,base,p["H"],closed)
            let contour=try inward(loopAt(source,z,p),p["W"]/2+p["EF"]*ef(t),z,p)
            let result=sampled(contour,n,seam:ref ?? bottoms.last?.last,angle:angle)
            cache[key]=result;sectionCount+=1
            if sectionCount>2500 {throw SliceFailure("Too many section refinements; simplify surface or lower accuracy")}
            return result
        }
        var times=[0.0],sections=[try section(0)],tt=0.0
        while tt<turns-1e-9 {try SliceComputation.check();let next=min(turns,tt+0.25);sections.append(try section(next,sections.last![0]));times.append(next);tt=next}
        var j=0
        while j<times.count-1 {
            let a=times[j],b=times[j+1],mid=(a+b)/2,actual=try section(mid,sections[j][0])
            let error=(0..<n).map{xyLength(actual[$0],(sections[j][$0]+sections[j+1][$0])/2)}.max()!
            if error>p["Tolerance"] {
                if b-a<1/256.0 {throw SliceFailure(String(format:"Abrupt section / seam change around Z=%.3f",base+p["H"]*mid))}
                times.insert(mid,at:j+1);sections.insert(actual,at:j+1)
            } else {j+=1}
        }
        func at(_ t:Double)->SlicePoint {
            let j=min(times.count-2,max(0,upperBound(times,t)-1)),u=(t-times[j])/(times[j+1]-times[j])
            let f=modulo(t,1)*Double(n),k=Int(f)%n,v=f-Double(Int(f)),left=sections[j],right=sections[j+1]
            return (1-u)*((1-v)*left[k]+v*left[(k+1)%n])+u*((1-v)*right[k]+v*right[(k+1)%n])
        }
        var ring=[SlicePoint](),ringE=[Double?](),ringGaps=[Double](),wall=[at(0)],we=[Double?](),wg=[Double]()
        var shift=SlicePoint.zero
        if let end=bottoms.last?.last {
            shift=SlicePoint(end.x-wall[0].x,end.y-wall[0].y,0)
            if hypot(shift.x,shift.y)>min(p["W"],p["WB"])/2+p["Tolerance"] {throw SliceFailure("Bottom-to-wall mismatch too large; match widths or simplify base slope")}
            wall[0]=end
            if hypot(shift.x,shift.y)>0.01 {notes.append("接墙首圈平滑消除底部终点偏移，保持一笔连接。")}
        } else {
            ring=sections[0]+[sections[0][0]]
            ringE=(0..<n).map{xyLength(ring[$0],ring[$0+1])*beadArea(p["W"],p["H0"])};ringGaps=Array(repeating:p["H0"],count:n)
        }
        let nw=Int(ceil(turns*Double(n)))
        for i in 1...nw {
            if i & 255 == 0 {try SliceComputation.check()}
            let t=min(Double(i)/Double(n),turns),fade=1-smooth(t),ca=cos(tau*t),sa=sin(tau*t)
            var q=at(t);q+=fade*SlicePoint(shift.x*ca-shift.y*sa,shift.x*sa+shift.y*ca,0)
            let previous=Double(i-1)/Double(n),mid=(previous+t)/2
            let gap=closed ? turnZ(mid,height,base,p["H"],true)-turnZ(max(0,mid-1),height,base,p["H"],true):p["H"]*min(1,mid)
            if i>n && xyLength(q,wall[i-n])>(p["W"]-p["H"]*edge)/2+p["Tolerance"] {throw SliceFailure(String(format:"Wall overhang / per-turn offset exceeds half bead width near Z=%.3f",q.z))}
            we.append(xyLength(wall.last!,q)*beadArea(p["W"],gap));wg.append(gap);wall.append(q)
        }
        let top=sections.last!,fraction=modulo(turns,1)*Double(n)
        var terminal=(0...n).map {i -> SlicePoint in let f=modulo(fraction+Double(i),Double(n)),k=Int(f),v=f-Double(k);return (1-v)*top[k]+v*top[(k+1)%n]}
        terminal[0]=wall.last!;terminal[n]=wall.last!
        let allPoints=(bottoms+[ring,wall]).flatMap{$0}
        guard allPoints.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}) else {throw SliceFailure("Nonfinite path")}
        for path in [ring,wall] where path.count>1 {
            if (1..<path.count).contains(where:{xyLength(path[$0-1],path[$0])>max(p["W"],p["WB"],filament ? 3.01:0)}) {throw SliceFailure("Long extrusion jump detected")}
        }
        var candidate:[String:Any]=["points":coordinates(terminal)]
        if p.flag("AlignLeft") {candidate["gap"]=height-base-(turns-1)*p["H"]}
        let applied=(edgeReport?.segments ?? 0)>0
        var metadata=["; PATH_SCHEMA=G1_GEOMETRY_V1","; HAS_BOTTOM=\(bottoms.isEmpty ? 0:1)","; BOTTOM_PATTERN="+(bottoms.isEmpty ? "NONE":p.text("BottomPattern",fallback:"Spiral").uppercased()),
            "; OUTER_FIX_ELIGIBLE=\(eligible ? 1:0)","; OUTER_FIX_APPLIED=\(applied ? 1:0)","; G1_FINISH_CANDIDATE="+(try json(candidate)),
            "; E_UNITS=VOLUME_MM3","; GINGER_PELLET_FLOW_COEFFICIENT=1","; COMBINED_FLOW_MULTIPLIER=1","; FIRST_LAYER_FLOW_MULTIPLIER=1",
            "; PLACEMENT_CENTER_X=0 PLACEMENT_CENTER_Y=0","; H="+fmt(p["H"])+" W="+fmt(p["W"]),"; H0="+fmt(p["H0"])+" BH="+fmt(p["BH"]),
            "; FIRST_PATH_WIDTH="+fmt(bottoms.isEmpty ? p["W"]:p["WB"]),"; BOTTOM_LINE_WIDTH="+fmt(bottoms.isEmpty ? p["W"]:p["WB"]),
            "; BOTTOM_LAYERS=\(bottoms.count)","; BOTTOM_TOP_Z="+fmt(bottoms.isEmpty ? 0:base),"; TOTAL_HEIGHT="+fmt(height),
            "; EF_AMOUNT="+fmt(p["EF"])+" EF_FADE_WALL_TURNS=\(Int(p["EFLayers"]))","; EF_TURN_PERCENT="+(p.values["EFTurnPercent"] as? [Double] ?? []).map{fmt($0)}.joined(separator:","),
            "; G1_RAMP_APPLIED SOURCE=SHAPE_WORKBENCH","; ===== PRINT START =====","G90","G21","M83","G92 E0"]
        if applied,let report=edgeReport {
            metadata += ["; EDGE_CALIBRATION=MEASURED_20260912","; EDGE_CORRECTION_AFTER_EF=1","; EDGE_BASE_SKIRT_E_PER_MM="+fmt(report.baseRate),"; EDGE_BASE_SKIRT_FLOW="+fmt(report.flow),
                "; EDGE_RADIAL_KNOTS=0:\(fmt(p["EdgeDipOut"])),20:0,180:0,270:\(fmt(-p["EdgeBulgeIn"])),330:0,360:\(fmt(p["EdgeDipOut"]))","; EDGE_FLOW_PER_LENGTH_PRESERVED=1"]
        }
        metadata.insert("; BOTTOM_KIND="+p.text("BottomKind",fallback:"Annular").uppercased(),at:1)
        if !bottoms.isEmpty && ["Monotonic","Zigzag"].contains(p.text("BottomPattern")) {metadata.insert("; BOTTOM_ANGLES="+(try layerAngles(p)).map{fmt($0)}.joined(separator:","),at:2)}
        if p.flag("AlignLeft") {metadata.insert("; LEFT_ALIGNED=1",at:1)}
        let start=bottoms.first?.first ?? ring[0]
        var lines=metadata+["G1 Z"+fmt(start.z)+" F600","G1 X"+fmt(start.x)+" Y"+fmt(start.y)+" F3000"]
        func deposit(_ pts:[SlicePoint],_ es:[Double?],_ hs:[Double]) throws {
            let computation=SliceComputation.current
            for i in es.indices {
                if i & 255 == 0 {try computation?.check()}
                let q=pts[i+1],xyz="X"+fmt(q.x)+" Y"+fmt(q.y)+" Z"+fmt(q.z)
                guard let e=es[i] else {lines.append("G0 "+xyz+" F3000");continue}
                lines += ["; GH_GAP_HEIGHT="+fmt(max(hs[i],0.000001)),"G1 "+xyz+" E"+fmt(e)+" F420"]
            }
        }
        if !bottoms.isEmpty {
            lines.append("; ===== BOTTOM =====")
            for i in bottoms.indices {
                lines.append("; BOTTOM_LAYER=\(i+1)")
                if i>0 {
                    let q=bottoms[i][0]
                    lines.append(xyLength(bottoms[i-1].last!,q)>0.000001 ? "G0 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) F3000":"G1 Z\(fmt(q.z)) F600")
                }
                try deposit(bottoms[i],volumes[i],gaps[i])
            }
        }
        lines.append("; ===== WALL =====");try deposit(ring,ringE,ringGaps);try deposit(wall,we,wg);lines.append("; ===== PRINT PATH END =====")
        var info=String(format:"造型已更新 | %@ | 底 %d 层 | 墙 %.2f 圈 | 高 %.2f mm\nEF %g mm / %d 圈；底部全量，墙体逐圈递减。\n%@",p.text("SourceMode"),bottoms.count,turns,height,p["EF"],Int(p["EFLayers"]),notes.joined(separator:"\n"))
        if p.text("SourceMode")=="Imported" {info+="\n导入外形生成单壁；原模型壁厚不沿用。"}
        if p.flag("AlignLeft") {info+=String(format:"\n左侧对齐：首层与顶部同向；最后一圈上升 %.3f mm，总高度不变。",height-base-(turns-1)*p["H"])}
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:allPoints,wall:wall,bottoms:bottoms,volumes:volumes,source:source,sectionCount:sectionCount,details:["wallPath":Array(ring.dropLast())+wall])
    }
}
