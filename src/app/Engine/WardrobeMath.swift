import Foundation

final class WardrobeReference {
    let points:[SlicePoint],centers:[SlicePoint]
    struct ConnectorKey:Hashable {let inner:Double;let outer:Double}
    struct OuterKey:Hashable {let width:Double;let gap:Double;let bore:Double;let target:Double}
    var connectorCache=[ConnectorKey:([SlicePoint],[Double])](),outerCache=[OuterKey:Double]()
    init(resources:URL) throws {
        let raw=try SliceGeometry.readProfile(resources,"wardrobe_profile")
        points=(raw["points"] as! [[Double]]).map{SlicePoint($0[0],$0[1],0)};centers=(raw["centers"] as! [[Double]]).map{SlicePoint($0[0],$0[1],0)}
    }
    func plantOuterRadius(_ width:Double,_ gap:Double,_ bore:Double,_ target:Double=0) throws -> Double {
        let key=OuterKey(width:width,gap:gap,bore:bore,target:target);if let found=outerCache[key] {return found}
        guard target.isFinite,target>=0 else {throw SliceFailure("卷尖锁定净空须为非负有限数值。")}
        if width<=6 && target==0 {return 120}
        let target=target==0 ? SliceGeometry.plantTipClearance(6,gap,bore,120):target
        var low=120.0,high=200.0
        guard SliceGeometry.plantTipClearance(width,gap,bore,high)>=target else {throw SliceFailure("线宽过大，卷尖净空无法满足参考轮廓。")}
        for _ in 0..<16 {let mid=(low+high)/2;if SliceGeometry.plantTipClearance(width,gap,bore,mid)<target {low=mid}else{high=mid}}
        outerCache[key]=high;return high
    }
    func plantConnector(_ inner:Double,_ outer:Double=120) throws -> ([SlicePoint],[Double]) {
        let key=ConnectorKey(inner:inner,outer:outer);if let found=connectorCache[key] {return found}
        let span=510*Double.pi/180,r=outer,dr=4*(r-inner)/span,ddr=12*(r-inner)/(span*span),vx = -dr,vy=r,ax=r-ddr,ay=2*dr,heading=atan2(vy,vx),k0=(vx*ay-vy*ax)/pow(hypot(vx,vy),3)
        let start=SlicePoint(centers[0].x-r,centers[0].y,0),center=(centers[0]+centers[1])/2,target=center-start,count=4000
        func integrate(_ length:Double,_ power:Double,points:Bool=false)->([SlicePoint],SlicePoint) {
            var x=0.0,y=0.0,px=cos(heading),py=sin(heading),out=[start]
            for i in 1...count {let u=Double(i)/Double(count),angle=heading+k0*length/(power+1)*(1-pow(1-u,power+1)),tx=cos(angle),ty=sin(angle);x+=(px+tx)*length/(2*Double(count));y+=(py+ty)*length/(2*Double(count));px=tx;py=ty;if points {out.append(start+SlicePoint(x,y,0))}}
            return (out,SlicePoint(x,y,0))
        }
        var length=620.0,power=3.0,converged=false
        for _ in 0..<35 {
            let q=integrate(length,power).1,err=q-target,norm=hypot(err.x,err.y)
            if norm<1e-8 {converged=true;break}
            let dl=integrate(length+0.01,power).1,dp=integrate(length,power+0.0001).1,a=(dl.x-q.x)/0.01,c=(dl.y-q.y)/0.01,b=(dp.x-q.x)/0.0001,d=(dp.y-q.y)/0.0001,det=a*d-b*c
            guard abs(det)>=1e-12 else {throw SliceFailure("当前卷芯无法生成平顺 S 形。")}
            let dx=(d*err.x-b*err.y)/det,dy=(-c*err.x+a*err.y)/det;var accepted=false
            for factor in [1.0,0.5,0.25,0.125,0.0625,0.03125] {let ll=length-factor*dx,pp=power-factor*dy;if ll<=0 || pp<=1 {continue};let trial=integrate(ll,pp).1;if SliceGeometry.xyLength(trial,target)<norm {length=ll;power=pp;accepted=true;break}}
            guard accepted else {throw SliceFailure("当前卷芯与固定管轴无法满足曲率单调约束。")}
        }
        guard converged else {throw SliceFailure("S 形数学求解未收敛。")}
        let points=integrate(length,power,points:true).0
        guard SliceGeometry.xyLength(points.last!,center)<=1e-6 else {throw SliceFailure("S 形中心定位误差过大。")}
        let result=(points,[length,power,k0]);connectorCache[key]=result;return result
    }
}

extension SliceGeometry {
    static func unit2(_ v:SlicePoint)->SlicePoint {v/hypot(v.x,v.y)}
    static func resample(_ poly:[SlicePoint],step:Double=2)->[SlicePoint] {
        var arc=[0.0];for i in 1..<poly.count {arc.append(arc.last!+xyLength(poly[i-1],poly[i]))}
        let n=Int(ceil(arc.last!/step));var out=[SlicePoint](),j=0
        for i in 0...n {let s=arc.last!*Double(i)/Double(n);while j<poly.count-2 && arc[j+1]<s {j+=1};let u=(s-arc[j])/(arc[j+1]-arc[j]);out.append(poly[j]+(poly[j+1]-poly[j])*u)}
        return out
    }
    static func naturalCoil(_ reduction:Double)->[SlicePoint] {
        let span=2.5*Double.pi-reduction*Double.pi/180,a=96/(2.5*Double.pi)
        return (0...800).map{i in let t=span*Double(i)/800,r=120-a*t;return SlicePoint(r*cos(Double.pi+t),r*sin(Double.pi+t),0)}
    }
    static func tightCoil(_ inner:Double,_ reduction:Double)->[SlicePoint] {
        let a=96/(2.5*Double.pi),outerSpan=Double.pi/2,span=2*Double.pi-reduction*Double.pi/180,r0=100.8,weights=[0.8380771663504112,0.8380771663504112,0.28948569443371874,0.20180896263080766]
        let controls=[r0,r0-a*span/9,r0-2*a*span/9]+weights.map{inner+(r0-inner)*$0}+Array(repeating:inner,count:3)
        var coil=(0...320).map{i -> SlicePoint in let t=outerSpan*Double(i)/320,r=120-a*t,angle=Double.pi+t;return SlicePoint(r*cos(angle),r*sin(angle),0)}
        for i in 1...360 {let u=Double(i)/360,r=quinticValue(controls,u),angle=Double.pi+outerSpan+span*u;coil.append(SlicePoint(r*cos(angle),r*sin(angle),0))}
        for i in 1...270 {let angle=Double.pi+outerSpan+span+Double(i)*Double.pi/180;coil.append(SlicePoint(inner*cos(angle),inner*sin(angle),0))}
        return coil
    }
    static func returnControls(_ radius:Double,_ half:Double)->[SlicePoint] {
        let length=half*14/3
        return [SlicePoint(-half,0,0),SlicePoint(-half,-length/5,0),SlicePoint(-half-length*length/(radius-half)/20,-2*length/5,0),SlicePoint(half-length*length/(radius+half)/20,-2*length/5,0),SlicePoint(half,-length/5,0),SlicePoint(half,0,0)]
    }
    static func returnLength(_ radius:Double,_ half:Double)->Double {
        let c=returnControls(radius,half),xs=c.map{$0.x},ys=c.map{$0.y},points=(0...160).map{i in SlicePoint(quinticValue(xs,Double(i)/160),quinticValue(ys,Double(i)/160),0)}
        return (1..<points.count).reduce(0){$0+xyLength(points[$1-1],points[$1])}
    }
    static func plantTipClearance(_ width:Double,_ gap:Double,_ bore:Double,_ outer:Double)->Double {
        let half=(width+gap)/2,r0=bore/2+half+width/2+0.15,span=510*Double.pi/180,a0=Double.pi+span,q0=SlicePoint(r0*cos(a0),r0*sin(a0),0),t=SlicePoint(sin(a0),-cos(a0),0),n=SlicePoint(-t.y,t.x,0),controls=returnControls(r0,half),xs=controls.map{$0.x},ys=controls.map{$0.y}
        let cap=(0...80).map{i -> SlicePoint in let u=Double(i)/80,x=quinticValue(xs,u),y=quinticValue(ys,u);return q0+x*n+y*t}
        var side=[SlicePoint]()
        for i in 0...1000 {let theta=Double.pi+(span-Double.pi)*Double(i)/1000,u=theta/span,r=r0+(outer-r0)*pow(u,4),dr=4*(outer-r0)*pow(u,3)/span,a=a0-theta,ca=cos(a),sa=sin(a),tt=unit2(SlicePoint(dr*ca+r*sa,dr*sa-r*ca,0)),normal=SlicePoint(-tt.y,tt.x,0);side.append(SlicePoint(r*ca,r*sa,0)-half*normal)}
        var minimum=Double.infinity
        for q in cap {for i in 1..<side.count {minimum=min(minimum,pointDistance(q,side[i-1],side[i]))}}
        return minimum-width
    }
    static func plantCoil(_ inner:Double,_ outer:Double=120) throws -> [SlicePoint] {
        guard inner>0,inner<outer else {throw SliceFailure("螺旋卷芯半径无效。")}
        let span=510*Double.pi/180
        return (0...6000).reversed().map{i in let t=span*Double(i)/6000,r=inner+(outer-inner)*pow(t/span,4),a=Double.pi+span-t;return SlicePoint(r*cos(a),r*sin(a),0)}
    }
}
