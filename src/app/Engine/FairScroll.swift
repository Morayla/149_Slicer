import Foundation

extension SliceGeometry {
    struct EulerJoin {let phase:Double,length:Double,alpha:Double,end:SlicePoint,curvature:Double,radialB:Double,maximum:Double}
    static func halfEuler(_ length:Double,_ alpha:Double,_ curvature:Double,steps:Int=96)->SlicePoint {
        let h=length/(2*Double(steps));var x=0.0,y=0.0
        for i in 0...steps {let s=Double(i)*h,angle=alpha+curvature*length/4-curvature*s*s/length,weight=(i==0 || i==steps) ? 1.0:(i%2==1 ? 4.0:2.0);x+=weight*cos(angle);y+=weight*sin(angle)}
        return SlicePoint(x*h/3,y*h/3,0)
    }
    static func solveEulerJoin(_ radius:Double,_ inner:Double,_ turns:Double,_ separation:Double) throws -> EulerJoin {
        let b=(radius-inner)/(tau*turns),curvature=(radius*radius+2*b*b)/pow(radius*radius+b*b,1.5),delta=atan(b/radius)
        func atPhase(_ phase:Double)->(Double,Double,Double,SlicePoint) {
            let alpha=phase-Double.pi/2-delta,targetY=radius*sin(phase);var low=1e-10,high=4*(Double.pi/2-alpha)/curvature
            for _ in 0..<38 {let length=(low+high)/2;if halfEuler(length,alpha,curvature).y<targetY {low=length}else{high=length}}
            let length=(low+high)/2,end=halfEuler(length,alpha,curvature);return (2*(end.x-radius*cos(phase)),length,alpha,end)
        }
        var low=Double.pi/2+delta+1e-5,high=Double.pi-1e-5
        let maximum=atPhase(low).0,minimum=atPhase(high).0
        guard minimum<=separation,separation<=maximum else {throw SliceFailure(String(format:"当前尺寸与圈数的平顺连接最大中心距为 %.2f mm；请减小两圆参考间距或增大参考圆外径。",maximum))}
        for _ in 0..<38 {let phase=(low+high)/2;if atPhase(phase).0>separation {low=phase}else{high=phase}}
        let phase=(low+high)/2,(actual,length,alpha,end)=atPhase(phase)
        guard abs(actual-separation)<=1e-6,abs(end.y-radius*sin(phase))<=1e-6 else {throw SliceFailure("平顺双螺旋连接求解未收敛，请调整间距。")}
        return EulerJoin(phase:phase,length:length,alpha:alpha,end:end,curvature:curvature,radialB:b,maximum:maximum)
    }
    static func fairOutline(_ diameter:Double,_ turns:Double,_ gap:Double,_ width:Double,_ rotation:Double,innerFloor:Double=0) throws -> ([SlicePoint],[String:Any]) {
        let radius=(diameter-width)/2,inner=max(width*0.75,radius*8/70,innerFloor)
        guard inner<radius else {throw SliceFailure("花瓶内卷回转空间不足，请增大参考圆外径或减小线宽。")}
        let step=min(width/3,1.5),samples=max(160,Int(ceil(tau*turns*radius/step))),separation=diameter+gap
        guard samples<=6000 else {throw SliceFailure("等距双螺旋采样过多，请减少圈数或减小尺寸。")}
        let join:EulerJoin
        do {join=try solveEulerJoin(radius,inner,turns,separation)}catch{throw SliceFailure(error.localizedDescription+String(format:" 当前参考圆外径 %.2f mm、参考间距 %.2f mm。",diameter,gap))}
        let right=(0...samples).map{i -> SlicePoint in let phi=tau*turns*Double(i)/Double(samples),r=radius-join.radialB*phi,a=join.phase-phi;return SlicePoint(separation/2+r*cos(a),r*sin(a),0)}
        let n=max(40,Int(ceil(join.length/(2*step)))),h=join.length/(2*Double(n));var positive=[SlicePoint.zero],x=0.0,y=0.0
        func angle(_ s:Double)->Double {join.alpha+join.curvature*join.length/4-join.curvature*s*s/join.length}
        for i in 0..<n {let s=Double(i)*h;x+=h/6*(cos(angle(s))+4*cos(angle(s+h/2))+cos(angle(s+h)));y+=h/6*(sin(angle(s))+4*sin(angle(s+h/2))+sin(angle(s+h)));positive.append(SlicePoint(x,y,0))}
        guard xyLength(positive.last!,right[0])<=1e-5 else {throw SliceFailure("平顺双螺旋采样误差过大，请调整尺寸。")}
        let bridge=positive.dropFirst().reversed().map{-$0}+positive
        let raw=right.reversed().map{-$0}+bridge.dropFirst().dropLast()+right,a=rotation*Double.pi/180,c=cos(a),s=sin(a)
        let points=raw.map{SlicePoint($0.x*c-$0.y*s,$0.x*s+$0.y*c,0)}
        return (points,["center_distance":separation,"turns":turns,"gap":gap,"outer_radius":radius,"inner_radius":inner,"lobe_points":right.count,"radial_pitch":tau*join.radialB,"entry_angle":join.phase,"transition_length":join.length,"transition_alpha":join.alpha,"transition_curvature":join.curvature,"max_reference_gap":join.maximum-diameter])
    }
    static func quinticValue(_ values:[Double],_ t:Double)->Double {
        let degree=values.count-1;var result=0.0,coefficient=1
        for (j,value) in values.enumerated() {
            result+=Double(coefficient)*pow(1-t,Double(degree-j))*pow(t,Double(j))*value
            if j<degree {coefficient=coefficient*(degree-j)/(j+1)}
        }
        return result
    }
    static func rotatePoints(_ points:[SlicePoint],_ degrees:Double,midY:Double=0)->[SlicePoint] {
        let a=degrees*Double.pi/180,c=cos(a),s=sin(a);return points.map{SlicePoint($0.x*c-($0.y-midY)*s,$0.x*s+($0.y-midY)*c,$0.z)}
    }
}
