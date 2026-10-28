import Foundation

extension SliceGeometry {
    static func circularLobe(_ radius:Double,_ inner:Double,_ turns:Double,_ step:Double)->([SlicePoint],Int) {
        let arc=1.5*Double.pi,remaining=tau*turns-arc,circleCount=max(90,Int(ceil(arc*radius/step))),spiralCount=max(90,Int(ceil(remaining*radius/step))),angle=3*Double.pi/4,ramp=0.08
        var points=(0...circleCount).map{i -> SlicePoint in let a=angle-arc*Double(i)/Double(circleCount);return SlicePoint(radius*cos(a),radius*sin(a),0)}
        for i in 1...spiralCount {let u=Double(i)/Double(spiralCount),q=u/ramp,eased=(u<ramp ? ramp*(pow(q,3)-0.5*pow(q,4)):u-ramp/2)/(1-ramp/2),r=inner+(radius-inner)*pow(1-eased,2),a=angle-arc-remaining*u;points.append(SlicePoint(r*cos(a),r*sin(a),0))}
        return (points,circleCount)
    }
    static func circularScrollOutline(_ diameter:Double,_ turns:Double,_ gap:Double,_ width:Double,_ rotation:Double) throws -> ([SlicePoint],[String:Any]) {
        let radius=(diameter-width)/2,inner=max(width*0.9,radius*0.16),step=min(width/4,1.0)
        guard tau*turns*radius/step<=6000 else {throw SliceFailure("圆弧双卷采样过多，请减少圈数或减小尺寸。")}
        let (lobe,circleCount)=circularLobe(radius,inner,turns,step),separation=diameter+gap,right=lobe.map{$0+SlicePoint(separation/2,0,0)},start = -right[0],end=right[0]
        let tangent=SlicePoint(sqrt(0.5),sqrt(0.5),0),normal=SlicePoint(-tangent.y,tangent.x,0),speed=xyLength(start,end),b1=start+speed*tangent/5,b2=2*b1-start+speed*speed/radius*normal/20,controls=[start,b1,b2,-b2,-b1,end]
        let length=(1..<controls.count).reduce(0){$0+xyLength(controls[$1-1],controls[$1])},steps=max(16,Int(ceil(length/step)))
        let bridge=(1..<steps).map{i -> SlicePoint in let t=Double(i)/Double(steps);return SlicePoint(quinticValue(controls.map{$0.x},t),quinticValue(controls.map{$0.y},t),0)}
        let points=rotatePoints(right.reversed().map{-$0}+bridge+right,rotation);try checkSpacing(points,width:width,closed:false)
        return (points,["center_distance":separation,"turns":turns,"gap":gap,"circle_radius":radius,"circle_count":circleCount,"lobe_points":right.count,"bridge_controls":controls])
    }
    static func doubleOutline(_ diameter:Double,_ turns:Double,_ gap:Double,_ width:Double,_ rotation:Double=0,profile:Int=0,innerFloor:Double=0) throws -> ([SlicePoint],[String:Any]) {
        guard [diameter,turns,gap,width,rotation].allSatisfy(\.isFinite) else {throw SliceFailure("双螺旋参数必须为有限数值。")}
        guard (1...4).contains(turns) else {throw SliceFailure("每侧螺旋圈数须在 1–4 圈之间，可输入小数。")}
        guard gap>=0 else {throw SliceFailure("双螺旋外缘间距不能为负数。")}
        guard (0...3).contains(profile) else {throw SliceFailure("双螺旋轮廓样式无效。")}
        guard width>0,diameter>4*width else {throw SliceFailure("单瓣外径须大于四倍线宽。")}
        if profile==3 {let result=try fairOutline(diameter,turns,gap,width,rotation,innerFloor:innerFloor);try checkSpacing(result.0,width:width,closed:false);return result}
        if profile==2 {return try circularScrollOutline(diameter,turns,gap,width,rotation)}
        let radius=(diameter-width)/2,inner=max(width*0.75,radius*13/85.5),samples=max(160,Int(ceil(tau*turns*radius/min(width/3,1.5))))
        guard samples<=6000 else {throw SliceFailure("双螺旋采样过多，请减少圈数或减小尺寸。")}
        var right=(0...samples).map{i -> SlicePoint in let t=Double(i)/Double(samples),r=radius+(inner-radius)*t,a=(profile != 0 ? 3*Double.pi/4:Double.pi/2)-tau*turns*t;return SlicePoint(r*cos(a),r*sin(a),0)}
        let innerEdge=right.map{$0.x}.min()!-width/2,separation=gap-2*innerEdge;right=right.map{$0+SlicePoint(separation/2,0,0)}
        var points=right.reversed().map{SlicePoint(-$0.x,profile != 0 ? -$0.y:$0.y,0)}
        if profile != 0 {
            let start=points.last!,end=right[0],angle=3*Double.pi/4,dr=inner-radius,da = -tau*turns
            var tx=dr*cos(angle)-radius*sin(angle)*da,ty=dr*sin(angle)+radius*cos(angle)*da;let length=hypot(tx,ty);tx/=length;ty/=length
            let handle=xyLength(start,end)/3,c1=start+SlicePoint(tx*handle,ty*handle,0),c2=end-SlicePoint(tx*handle,ty*handle,0),steps=max(8,Int(ceil((xyLength(start,c1)+xyLength(c1,c2)+xyLength(c2,end))/min(width/3,1.5))))
            for i in 1..<steps {let t=Double(i)/Double(steps),u=1-t;points.append(pow(u,3)*start+3*u*u*t*c1+3*u*t*t*c2+pow(t,3)*end)}
        }else{
            let steps=max(1,Int(ceil(separation/min(width/3,1.5))));if steps>1 {for i in 1..<steps {points.append(SlicePoint(-separation/2+separation*Double(i)/Double(steps),radius,0))}}
        }
        points += right
        let midY=(points.map{$0.y}.min()!+points.map{$0.y}.max()!)/2;points=rotatePoints(points,rotation,midY:midY)
        try checkSpacing(points,width:width,closed:false);return (points,["center_distance":separation,"turns":turns,"gap":gap])
    }
    static func returnOutline(_ diameter:Double,_ turns:Double,_ gap:Double,_ width:Double,_ laneGap:Double,_ rotation:Double=0,profile:Int=0,innerFloor:Double=0) throws -> ([SlicePoint],[String:Any]) {
        guard laneGap.isFinite,laneGap>=0 else {throw SliceFailure("双线净间隙必须为非负有限数值。")}
        let d=(width+laneGap)/2
        var (spine,info)=try doubleOutline(diameter-2*d,turns,gap+2*d,width,0,profile:profile,innerFloor:innerFloor)
        let tangents=(1..<spine.count).map{(spine[$0]-spine[$0-1])/xyLength(spine[$0-1],spine[$0])},normals=tangents.map{SlicePoint(-$0.y,$0.x,0)}
        var left=[SlicePoint](),right=[SlicePoint]()
        for (i,p) in spine.enumerated() {
            let normal:SlicePoint
            if i==0 {normal=normals[0]}else if i==spine.count-1 {normal=normals.last!}else{let a=normals[i-1],b=normals[i],den=1+a.x*b.x+a.y*b.y;guard den>=0.1 else {throw SliceFailure("双线转角过急，请调整圈数或尺寸。")};normal=(a+b)/den}
            left.append(p+d*normal);right.append(p-d*normal)
        }
        let capCount=max(16,Int(ceil(Double.pi*d/min(width/4,1))))
        func cap(_ p:SlicePoint,_ normal:SlicePoint)->[SlicePoint] {let angle=atan2(normal.y,normal.x);return (1..<capCount).map{let a=angle-Double.pi*Double($0)/Double(capCount);return p+SlicePoint(d*cos(a),d*sin(a),0)}}
        let poly=left+cap(spine.last!,normals.last!)+right.reversed()+cap(spine[0],-normals[0])
        do {try checkSpacing(poly,width:width)}catch{throw SliceFailure("双线螺旋空间不足或路径相交：请减少圈数、增大单瓣外径，或减小双线净间隙。")}
        let midY=(poly.map{$0.y}.min()!+poly.map{$0.y}.max()!)/2;var points=rotatePoints(poly,rotation,midY:midY);points.append(points[0])
        info["gap"]=gap;info["lane_gap"]=laneGap;info["lines"]=2;return (points,info)
    }
}
