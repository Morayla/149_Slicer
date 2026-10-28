import Foundation

extension SliceGeometry {
    static func crescentOutline(_ diameter:Double,_ thickness:Double,_ gap:Double,_ width:Double,_ rotation:Double) throws -> [SlicePoint] {
        guard [diameter,thickness,gap,width,rotation].allSatisfy(\.isFinite) else {throw SliceFailure("弯月参数必须为有限数值。")}
        let radius=diameter/2
        guard width>0,2.25*width<thickness,thickness<radius else {throw SliceFailure("月牙最厚处须大于 2.25 倍线宽，且小于外圆半径。")}
        guard gap>0,gap<diameter/2 else {throw SliceFailure("开口净宽须大于 0，且小于外径的一半。")}
        let ro=radius-width/2,capRadius=width*0.625,capCenter=ro-capRadius
        guard (gap+2.25*width)/(2*capCenter)<1 else {throw SliceFailure("开口或线宽过大，请增大外径。")}
        let alpha=asin((gap+2.25*width)/(2*capCenter)),sweep=tau-2*alpha,n=max(256,Int(ceil(ro*sweep/min(width/4,1))))
        guard n<=6000 else {throw SliceFailure("弯月轮廓过密，请减小外径或增大线宽。")}
        var outer=[SlicePoint](),inner=[SlicePoint]()
        for i in 0...n {
            let u=Double(i)/Double(n),a=alpha+sweep*u,s=sin(Double.pi*u),separation=1.25*width+(thickness-2.25*width)*s*s
            outer.append(SlicePoint(ro*cos(a),ro*sin(a),0));inner.append(SlicePoint((ro-separation)*cos(a),(ro-separation)*sin(a),0))
        }
        func cap(_ a:Double,_ start:Double)->[SlicePoint] {(1..<25).map{i in let phi=start+Double.pi*Double(i)/25,r=capCenter+capRadius*cos(phi),t=capRadius*sin(phi);return SlicePoint(r*cos(a)-t*sin(a),r*sin(a)+t*cos(a),0)}}
        let angle=rotation*Double.pi/180,c=cos(angle),s=sin(angle)
        var points=(outer+cap(tau-alpha,0)+inner.reversed()+cap(alpha,Double.pi)).map{SlicePoint($0.x*c-$0.y*s,$0.x*s+$0.y*c,$0.z)};points.append(points[0])
        do {try checkSpacing(Array(points.dropLast()),width:width)}catch {throw SliceFailure("弯月料道过近，请增大外径或减小厚度、线宽。")}
        return points
    }
    static func crescentModel(_ p:SliceParameters) throws -> SliceShape {
        let width=p["W"],height=p["CH"],first=p["H0"],pitch=p["H"]
        guard height>=first else {throw SliceFailure("总高度不能小于首层层高。")}
        var path=try crescentOutline(p["CrescentD"],p["CrescentThickness"],p["CrescentGap"],width,p["CrescentRotation"])
        let bulb=p["CrescentBulbD"],clearance=p["CrescentD"]/2-p["CrescentThickness"]-bulb/2
        guard bulb>0,clearance>0 else {throw SliceFailure("正中心的灯泡参考范围与月牙相交；请减小灯泡直径或月牙厚度。")}
        if p.flag("AlignLeft") {var poly=Array(path.dropLast());let i=poly.indices.min{poly[$0].x==poly[$1].x ? poly[$0].y<poly[$1].y:poly[$0].x<poly[$1].x}!;poly=Array(poly[i...])+poly[..<i];path=poly+[poly[0]]}
        let count=1+max(0,Int(ceil((height-first)/pitch-1e-9)))
        guard count*path.count<=220_000 else {throw SliceFailure("弯月路径超过 22 万段，请降低高度或增大层高。")}
        var lines=["; PATH_SCHEMA=G1_GEOMETRY_V1","; SHAPE_KIND=CRESCENT","; HAS_BOTTOM=0","; BOTTOM_LAYERS=0","; BOTTOM_PATTERN=NONE","; OUTER_FIX_ELIGIBLE=0","; OUTER_FIX_APPLIED=0","; EF_AMOUNT=0","; E_UNITS=VOLUME_MM3","; GINGER_PELLET_FLOW_COEFFICIENT=1","; COMBINED_FLOW_MULTIPLIER=1","; FIRST_LAYER_FLOW_MULTIPLIER=1","; H=\(fmt(pitch)) W=\(fmt(width))","; H0=\(fmt(first)) BH=\(fmt(pitch))","; FIRST_PATH_WIDTH="+fmt(width),"; BOTTOM_LINE_WIDTH="+fmt(width),"; TOTAL_HEIGHT="+fmt(height),"; PLACEMENT_CENTER_X=0 PLACEMENT_CENTER_Y=0","; ===== PRINT START =====","G90","G21","M83","G92 E0","G0 Z"+fmt(first)+" F600","G0 X\(fmt(path[0].x)) Y\(fmt(path[0].y)) F3000","; ===== WALL ====="]
        var wall=[SlicePoint](),previous=0.0
        for layer in 0..<count {
            let z=min(height,first+Double(layer)*pitch),h=z-previous;previous=z
            let points=path.map{SlicePoint($0.x,$0.y,z)}
            if layer>0 {lines.append("G0 Z"+fmt(z)+" F600")};lines.append("; GH_WALL_TURN=\(layer)")
            for i in 1..<points.count {let b=points[i];lines += ["; GH_GAP_HEIGHT="+fmt(h),"G1 X\(fmt(b.x)) Y\(fmt(b.y)) Z\(fmt(z)) E\(fmt(xyLength(points[i-1],b)*beadArea(width,h))) F420"]}
            wall += points
        }
        lines.append("; ===== PRINT PATH END =====")
        let info=String(format:"单弯月灯罩 | 外径 %g mm | 高 %g mm | 月牙厚度 %g mm | 开口净宽 %g mm。\n一条闭合的月牙轮廓逐层打印，两端圆滑回转。月牙内部为空心壳体，不整块填实；不生成底盘或灯座。\n灯泡参考直径 %g mm，固定在外圆正中心；最小平面净距约 %.2f mm。参考标记不出料。\n本造型不应用 EF、首层外缘校准或波形效果，原有参数仍保存在项目中。",p["CrescentD"],height,p["CrescentThickness"],p["CrescentGap"],bulb,clearance)
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:wall,wall:wall,sectionCount:1,details:["crescent":["path":path,"bulb_diameter":bulb,"clearance":clearance]])
    }
}
