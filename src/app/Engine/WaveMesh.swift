import Foundation

extension SliceGeometry {
    static func applyMesh(_ model:SliceShape,_ raw:SliceParameters) throws -> SliceShape {
        if !raw.flag("MeshEnabled") {return model}
        let p=model.parameters
        guard !raw.flag("WaveEnabled") else {throw SliceFailure("波浪网孔与三角波不能同时启用。")}
        guard ["Cylinder","Ellipse"].contains(p.text("SourceMode")) else {throw SliceFailure("波浪网孔目前支持圆柱和椭圆柱。")}
        guard p["EF"]<=0 else {throw SliceFailure("波浪网孔需要上下轮廓对齐，请先关闭 EF 象脚补偿。底部设置仍保留。")}
        guard ["MeshCount","MeshOpening","MeshStrand","MeshSpeed"].allSatisfy({raw[$0].isFinite && raw[$0]>0}) else {throw SliceFailure("网孔参数必须为正有限数值。")}
        let requested=raw["MeshCount"],strand=raw["MeshStrand"],opening=raw["MeshOpening"],speed=raw["MeshSpeed"],press=raw["MeshContactPress"],land=raw["MeshContactLength"]
        guard (2...300).contains(requested) else {throw SliceFailure("网孔每圈波数请输入 2–300。")}
        let n=max(2.5,min(299.5,ceil(requested)-0.5)),contact=strand-press
        guard press.isFinite,press>=0,press<=strand*0.25 else {throw SliceFailure("接点压合量请输入 0 到料线厚度的 25% 之间。")}
        guard land.isFinite,land>=0 else {throw SliceFailure("接点搭接长度必须为非负有限数值。")}
        guard strand<=p["W"] else {throw SliceFailure("料线厚度不能大于外墙线宽；请减小料线厚度或增大线宽。")}
        guard speed<=100 else {throw SliceFailure("网孔走线速度请输入不超过 100 mm/s。")}
        let wall=model.wall,base=wall[0].z,height=p["CH"],span=height-base,nominalPitch=contact+(opening+press)/2,turns=max(1,Int(ceil((span+(opening+press)/2)/nominalPitch-1e-10)))
        guard turns>=4,span/Double(turns)>contact*1.05 else {throw SliceFailure("高度不足以形成网孔及首尾过渡；请增大总高度或减小网孔高度、料线厚度。")}
        let amplitude=(span-Double(turns)*contact)/(2*Double(turns-1)),pitch=contact+2*amplitude,actualOpening=4*amplitude-press
        guard actualOpening>0 else {throw SliceFailure("接点压合后网孔消失，请减小压合量或增大网孔高度。")}
        let angle=atan2(wall[0].y,wall[0].x),circumference:Double,xy:(Double)->SlicePoint
        if p.text("SourceMode")=="Ellipse" {
            let contour=try inward(.polygon(model.source!.loop(base),base),p["W"]/2,base,p)
            guard case let .polygon(poly,_)=contour else {throw SliceFailure("Missing ellipse contour")}
            let points=sampledPolygon(poly,z:0,count:max(1024,poly.count*2),angle:angle),path=Polyline(points+[points[0]])
            circumference=points.indices.reduce(0){$0+xyLength(points[$1],points[($1+1)%points.count])};xy={path.at($0)}
        }else{let r=hypot(wall[0].x,wall[0].y);circumference=tau*r;xy={SlicePoint(r*cos(angle+tau*$0),r*sin(angle+tau*$0),0)}}
        guard circumference/n>=p["W"]*1.5 else {throw SliceFailure("网孔过密，料线可能连成实墙；请减少波数或减小外墙线宽。")}
        let wavelength=circumference/n
        guard land<=wavelength/4 else {throw SliceFailure(String(format:"接点搭接长度不能超过一个波长的 25%%（当前上限 %.3g mm）。",wavelength/4))}
        var samples=max(256,Int(ceil(n*32)),Int(ceil(circumference/1.5)));let halfwaves=Int(n*2);samples=halfwaves*max(16,Int(ceil(Double(samples)/Double(halfwaves))))
        var fractions=(1...samples).map{Double($0)/Double(samples)}
        if land>0 {
            var sites=Set(fractions)
            for k in 0..<halfwaves {let center=(Double(k)+0.5)/Double(halfwaves);for offset in [-0.5,-0.25,0,0.25,0.5] {sites.insert(center+offset*land/circumference)}}
            fractions=Set(sites.map{Double(fmt($0,places:12))!}).sorted();samples=fractions.count
        }
        guard samples*turns<=180_000 else {throw SliceFailure("网孔路径过密，请减少高度或波数。")}
        func envelope(_ t:Double)->Double {let u=max(0,min(1,t,Double(turns)-t));return u*u*(3-2*u)}
        func rise(_ t:Double)->Double {let whole=floor(t),u=t-whole,previous=whole==0 ? 0:whole-1+u*u*(3-2*u);return contact*t+amplitude*(envelope(t)+2*previous)}
        func wave(_ t:Double)->Double {
            if land==0 {return sin(tau*n*t)}
            let phase=modulo(tau*n*t+Double.pi/2,tau),half=Int(phase/Double.pi),delta=Double.pi*land/wavelength,u=max(0,min(1,(phase-Double(half)*Double.pi-delta)/(Double.pi-2*delta))),ease=u*u*u*(10+u*(-15+6*u))
            return (-1+2*ease)*(half==0 ? 1:-1)
        }
        var points=[wall[0]],moves=["; GH_WALL_TURN=1"];let area=beadArea(p["W"],strand)
        for i in 1...samples*turns {
            if i>1 && (i-1)%samples==0 {moves.append("; GH_WALL_TURN=\((i-1)/samples+1)")}
            let t=Double((i-1)/samples)+fractions[(i-1)%samples];var q=xy(t);q.z=base+rise(t)+amplitude*envelope(t)*wave(t)
            let d=distance3(points.last!,q);moves += ["; GH_GAP_HEIGHT="+fmt(strand),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(area*d)) F\(fmt(speed*60))"];points.append(q)
        }
        let lines=SliceGcode.lines(model.gcode)
        guard let first=try SliceGcode.records(model.gcode).0.first(where:{$0.extrusion != nil && $0.section=="WALL" && ($0.after.z ?? 0)>base+1e-7})?.line else {throw SliceFailure("Missing rising wall")}
        let cut=lines[first-1].hasPrefix("; GH_GAP_HEIGHT=") ? first-1:first
        var text=(Array(lines[..<cut])+["; MESH_PROCESS_BEGIN"]+moves+["; MESH_PROCESS_END","; ===== PRINT PATH END ====="]).filter{!$0.hasPrefix("; G1_FINISH_CANDIDATE=")}.joined(separator:"\n")
        for (key,value) in [("NONPLANAR_MODE","WAVE_MESH_V1"),("TOTAL_HEIGHT",fmt(height)),("MESH_COUNT",fmt(n)),("MESH_OPENING",fmt(actualOpening)),("MESH_STRAND",fmt(strand)),("MESH_CONTACT_PRESS",fmt(press)),("MESH_CONTACT_LENGTH",fmt(land)),("MESH_CONTACT_MODE",press != 0 || land != 0 ? "CONTACT_LAND_V3":"COUPLED_RISE_V2")] {text=SliceGcode.setMeta(text,key,value)}
        var output=model;output.gcode=text;output.wall=points
        output.details["mesh"]=["requested":requested,"effective":n,"opening":actualOpening,"pitch":pitch,"turns":turns,"contact_gap":contact,"contact_press":press,"contact_length":land] as [String:Any]
        output.info=String(format:"波浪网孔（实验）：%g → %g 波/圈；适配高度后的最大网孔高度 %.2f mm，料线厚度 %g mm，共 %d 圈。\n首尾各一圈渐变，主体上下圈错开半波。出料按三维料线长度计算，不填满网孔；预览不模拟下垂或粘接。\n需要验证跨空段成形及喷嘴侧面间隙，建议先打印低速短样品。\n底部和平面墙脚保持原设置；总高度 %g mm。",requested,n,actualOpening,strand,turns,height)
        if press != 0 || land != 0 {output.info+=String(format:"\n接点间距 %.3f mm；压合量 %.3f mm；沿轮廓搭接 %.3f mm。保留料线截面积，接点连续走线、不停顿。",contact,press,land)}
        return output
    }
}
