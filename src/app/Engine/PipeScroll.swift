import Foundation

extension SliceGeometry {
    static let pipeInner=29.7/2+(6.0+3.0)/2+6.0/2+0.15
    static func pairedPipeOutline(_ spine:[SlicePoint],normals:[SlicePoint],half:Double,tolerance:Double) throws -> [SlicePoint] {
        let lanes=[1.0,-1.0].map{sign in zip(spine,normals).map{$0+sign*half*$1}},controls=returnControls(pipeInner,half),xs=controls.map{$0.x},ys=controls.map{$0.y}
        var caps=[[SlicePoint]]()
        for (index,sign) in [(0,1.0),(spine.count-1,-1.0)] {
            let point=spine[index],normal=normals[index],tangent=SlicePoint(normal.y,-normal.x,0)
            caps.append((0...80).map{i in let x=quinticValue(xs,Double(i)/80),y=quinticValue(ys,Double(i)/80);return point+x*normal+sign*y*tangent})
        }
        var poly=[SlicePoint]()
        for piece in [lanes[0],Array(caps[1].reversed()),Array(lanes[1].reversed()),caps[0]] {
            var points=simplify(piece,tolerance:tolerance)
            if let previous=poly.last {guard xyLength(previous,points[0])<1e-8 else {throw SliceFailure("插管轮廓接点不连续。")};points.removeFirst()};poly+=points
        }
        guard xyLength(poly[0],poly.last!)<1e-8 else {throw SliceFailure("插管轮廓未闭合。")};poly.removeLast();try checkSpacing(poly,width:6);return poly
    }
    static func pipeBores(_ poly:[SlicePoint],separation:Double)->[Double] {
        [SlicePoint(separation/2,0,0),SlicePoint(-separation/2,0,0)].map{center in 2*(poly.indices.map{pointDistance(center,poly[$0],poly[($0+1)%poly.count])}.min()!-3)}
    }
    static func pipeOutline(_ rotation:Double=0,separation:Double=150) throws -> ([SlicePoint],[String:Any]) {
        guard separation.isFinite,(120...230).contains(separation) else {throw SliceFailure("两卷芯中心距请设为 120–230 mm。")}
        let span=510*Double.pi/180,keep=270*Double.pi/180,half=4.5
        let q=(0...1800).map{i -> SlicePoint in let t=span*Double(i)/1800,u=max(0,(t-keep)/(span-keep)),r=pipeInner+(120-pipeInner)*pow(t/span,4)-(120-90)*pow(u,3),a=225*Double.pi/180+span-t;return SlicePoint(r*cos(a),r*sin(a),0)}
        let right=q.map{$0+SlicePoint(separation/2,0,0)},a=right.last!,b = -a,tangent=unit2(q.last!-q[q.count-2]),handle=xyLength(a,b)*0.47,c=a+handle*tangent,e=b-handle*tangent
        let bridge=(1..<400).map{i -> SlicePoint in let u=Double(i)/400,v=1-u;return pow(v,3)*a+3*v*v*u*c+3*v*u*u*e+pow(u,3)*b}
        let spine=right+bridge+right.reversed().map{-$0},normals=spine.indices.map{i -> SlicePoint in let d=spine[min(spine.count-1,i+1)]-spine[max(0,i-1)],length=hypot(d.x,d.y);return SlicePoint(-d.y/length,d.x/length,0)}
        let poly=try pairedPipeOutline(spine,normals:normals,half:half,tolerance:0.035),bores=pipeBores(poly,separation:separation)
        guard bores.min()!>=29.7-0.02 else {throw SliceFailure("插管卷芯净空不足。")}
        var path=rotatePoints(poly,rotation);path.append(path[0])
        return (path,["core_bores":bores,"pipe_diameter":21.3,"retained_inner_degrees":270,"center_distance":separation,"turns":510.0/360,"gap":3.0,"lines":2])
    }
    static func centeredPipeOutline(_ rotation:Double = -6.4,separation:Double=215) throws -> ([SlicePoint],[String:Any]) {
        guard separation.isFinite,(180...230).contains(separation) else {throw SliceFailure("同心顺滑版中心距请设为180–230 mm；确认版为215 mm。")}
        let (original,info)=try doubleOutline(171,1.5,separation-171,6,0,profile:3,innerFloor:10.5),n=info["lobe_points"] as! Int,phase=info["entry_angle"] as! Double,b=(info["radial_pitch"] as! Double)/tau,join=270*Double.pi/180,span=join,r1=10.5+b*join
        let controls=[pipeInner,pipeInner,pipeInner,r1-2*b*span/5,r1-b*span/5,r1]
        let right=original.suffix(n).enumerated().map{i,q -> SlicePoint in let t=tau*1.5*(1-Double(i)/Double(n-1));if t>=join {return q};let r=quinticValue(controls,t/span),a=phase-tau*1.5+t;return SlicePoint(separation/2+r*cos(a),r*sin(a),0)}
        let spine=right.reversed().map{-$0}+original[n..<original.count-n]+right
        var normals=spine.indices.map{i -> SlicePoint in let d=spine[min(spine.count-1,i+1)]-spine[max(0,i-1)],length=hypot(d.x,d.y);return SlicePoint(-d.y/length,d.x/length,0)}
        let a=phase-tau*1.5;normals[normals.count-1]=SlicePoint(cos(a),sin(a),0);normals[0]=normals.last!
        let poly=try pairedPipeOutline(spine,normals:normals,half:4.5,tolerance:0.02),bores=pipeBores(poly,separation:separation)
        let d1=(1..<controls.count).map{5*(controls[$0]-controls[$0-1])/span},d2=(1..<d1.count).map{4*(d1[$0]-d1[$0-1])/span}
        let curvatures=(0...1000).map{i -> Double in let u=Double(i)/1000,r=quinticValue(controls,u),v=quinticValue(d1,u),acc=quinticValue(d2,u);return (r*r+2*v*v-r*acc)/pow(r*r+v*v,1.5)}
        guard curvatures.min()!>0,(1..<curvatures.count).allSatisfy({curvatures[$0]-curvatures[$0-1]<1e-8}),bores.min()!>29.7 else {throw SliceFailure("同心插管轮廓的曲率或净空校核未通过。")}
        var path=rotatePoints(poly,rotation);path.append(path[0])
        return (path,["core_bores":bores,"pipe_diameter":21.3,"center_distance":separation,"turns":1.5,"gap":3.0,"lines":2,"profile_name":"CENTERED_FAIR_PIPE_SCROLL"])
    }
    static func trimmedPipeOutline(_ rotation:Double,resources:URL) throws -> ([SlicePoint],[String:Any]) {
        guard rotation.isFinite else {throw SliceFailure("旋转角度须为有限数值。")}
        struct Profile:Decodable {let path:[[Double]];let bore:Double;let sep:Double}
        let raw=try JSONDecoder().decode(Profile.self,from:Data(contentsOf:resources.appendingPathComponent("trimmed_pipe_scroll_profile.json")))
        var path=rotatePoints(raw.path.map{SlicePoint($0[0],$0[1],0)},rotation);path.append(path[0])
        return (path,["core_bores":[raw.bore,raw.bore],"pipe_diameter":21.3,"center_distance":raw.sep,"turns":(540.0-35)/360,"gap":1.5,"lines":2,"sleeve_outer_diameter":25.7,"sleeve_inner_diameter":21.7])
    }
    static func pipeModel(_ p:SliceParameters,resources:URL) throws -> SliceShape {
        let profile=p["PipeScrollProfile"],expectedWidth=profile==2 ? 8.0:6.0
        guard abs(p["W"]-expectedWidth)<=1e-8 else {throw SliceFailure("当前插管轮廓的线宽请设为\(fmt(expectedWidth)) mm。")}
        guard p["H0"]+p["H"]<=p["CH"],p["CH"]<=1000 else {throw SliceFailure("插管型高度须包含首层和一圈墙体，且不超过 1000 mm。")}
        guard [0.0,1.0,2.0].contains(profile) else {throw SliceFailure("不支持的插管型轮廓。")}
        let data:([SlicePoint],[String:Any])
        if profile==2 {data=try trimmedPipeOutline(p["PipeScrollRot"],resources:resources)}else if profile==1 {data=try centeredPipeOutline(p["PipeScrollRot"],separation:p.values["PipeScrollSpacing"]==nil ? 215:p["PipeScrollSpacing"])}else{data=try pipeOutline(p["PipeScrollRot"],separation:p.values["PipeScrollSpacing"]==nil ? 150:p["PipeScrollSpacing"])}
        let info=data.1;var parameters=p;parameters.set(["DoubleTurns":info["turns"]!,"DoubleGap":info["gap"]!,"DoubleLaneGap":info["gap"]!])
        var model=try doubleVaseModel(parameters,outlineData:data)
        model.gcode=model.gcode.replacingOccurrences(of:"; DOUBLE_PROFILE=FAIR_ARCHIMEDEAN_SCROLL",with:"; DOUBLE_PROFILE=WARDROBE_PIPE_SCROLL\n; PIPE_SCROLL=1\n; PIPE_CORE_BORE=29.7\n; PIPE_DIAMETER=21.3")
        let bores=info["core_bores"] as! [Double],distance=info["center_distance"] as! Double,doubleInfo=model.details["double"] as! [String:Any],pitch=doubleInfo["actual_pitch"] as! Double,turns=doubleInfo["rise_turns"] as! Int
        model.info=String(format:"镜像双螺旋 · 插管型 | 高 %g mm\n内侧270°沿用衣架卷芯，外圈缩小；管径21.3 mm，卷芯设定内径29.7 mm，最小净空%.2f mm。\n两卷芯中心距%g mm；缩短连接段，卷芯保持原尺寸。\n线宽6 mm，双墙净隙3 mm；管与定位套另行装配，不生成其实体。\n首层等高闭合，随后连续升Z，顶部按剩余间隙整平；高度和旋转不改变插管接口。\n每圈实际上升%.4f mm；共%d圈。",p["CH"],bores.min()!,distance,pitch,turns)
        if profile==1 {
            model.gcode=model.gcode.replacingOccurrences(of:"WARDROBE_PIPE_SCROLL",with:"CENTERED_FAIR_PIPE_SCROLL")
            model.info=String(format:"同心顺滑双螺旋 · 原尺寸 | 高 %g mm\n两卷芯中心距%g mm；Ø21.3 mm管位于最内圈中心，使用独立定位套。\n卷芯设定内径29.7 mm，最小净空%.2f mm；实际定位套接触面需按原件核对。\n线宽6 mm，双墙净隙3 mm；外侧等距螺旋与中间欧拉连接保留，内侧270°曲率连续过渡。\n首层闭合、连续升Z、顶部整平；主体不打印管和定位套。\n每圈实际上升%.4f mm；共%d圈。",p["CH"],distance,bores.min()!,pitch,turns)
        }
        if profile==2 {
            model.gcode=model.gcode.replacingOccurrences(of:"WARDROBE_PIPE_SCROLL",with:"TRIMMED_W8_PIPE_SCROLL").replacingOccurrences(of:"; PIPE_CORE_BORE=29.7",with:String(format:"; PIPE_CORE_BORE=%.4f\n; SLEEVE_OUTER_DIAMETER=25.7",bores.min()!))
            model.info=String(format:"双螺旋 · 8毫米线宽 · 卷尖加回15° | 高 %g mm\n确认轮廓约285.2 × 118.3 mm，线宽8 mm，双墙净隙约1.5 mm。\n完整插套内孔Ø21.7、外径Ø25.7、壁厚2 mm，配Ø21.3 mm管。\n主体最小容纳直径%.2f mm；插套需要另用较细线宽打印并试装。\n当前切片和用料仅含绿色主体及裙边，不含管和两个蓝色插套。\n连续升Z，顶部整平；每圈实际上升%.4f mm，共%d圈。",p["CH"],bores.min()!,pitch,turns)
        }
        model.details["pipe_scroll"]=info;return model
    }
}
