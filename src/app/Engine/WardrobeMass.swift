import Foundation

extension SliceGeometry {
    static func frameMass(_ p:SliceParameters,material:SliceParameters,current:[String:Double],segments:[[Double]],lengths:[Double]) throws -> [String:Any] {
        let dims=try frameDimensions(p),beam=p["WardBeam"],half=(p["W"]+p["WardLaneGap"])/2,heights=[beam,dims["lower_height"]!,dims["lower_height"]!,dims["upper_height"]!,dims["upper_height"]!,beam]
        var volumes=[Double](),pathLengths=[Double]()
        for (i,h) in heights.enumerated() {
            let solid=[0,5].contains(i),r=dims[i>=3 ? "top_radius":"bottom_radius"]!,length=solid ? lengths.reduce(0,+):lengths[[1,3].contains(i) ? 0:1],base=solid ? length:length-p["WardOpening"]/2-(half+p["W"]/2)
            let area=base*h+(solid ? 0:r*r*edge),radius=(p.values["WardCoreBore"]==nil ? 30:p["WardCoreBore"])/2+half+p["W"]/2+0.15,cap=p["WardCoreMode"]==3 ? (returnLength(radius,half)-Double.pi*half)*(solid ? 2:1):0
            let pathArea=2*area+(tau*half+cap)*h,pitch=(h-p["H0"])/ceil((h-p["H0"])/(solid ? p["H"]:p["H"]*0.988)-1e-9)
            var volume=pathArea*(p["W"]-edge*pitch)
            let perimeter0=2*(base+(solid ? 0:r))+tau*half+cap,perimeter1=2*base+tau*half+cap
            volume+=edge*((pitch-p["H0"])*p["H0"]*perimeter0+pitch*pitch*(perimeter0+perimeter1)/6);volumes.append(volume)
            func cornerIntegral(_ z:Double)->Double {if solid{return 0};if z>=r{return r*r*edge};let t=max(0,r-z);return r*z-Double.pi*r*r/4+(t*sqrt(max(0,r*r-t*t))+r*r*asin(t/r))/2}
            func integral(_ z:Double)->Double {2*(base*z+cornerIntegral(z))+(tau*half+cap)*z}
            func perimeter(_ z:Double)->Double {let inset=solid ? 0:r-sqrt(max(0,r*r-pow(r-min(r,z),2)));return 2*(base+inset)+tau*half+cap}
            let first=p["H0"],spans=(!solid && p["WardLayerMode"]==0) ? [(first,min(h,r),p["H"]*0.60),(min(h,r),h,p["H"])]:[(first,h,solid ? p["H"]:p["H"]*0.988)]
            var path=perimeter(first)+perimeter(h)
            for (lo,hi,limit) in spans where hi>lo {let count=ceil((hi-lo)/limit-1e-9);path+=(integral(hi)-integral(lo))/((hi-lo)/count)};pathLengths.append(path)
        }
        let density=material["Density"],extra=material["ExtraWasteG"],selected=Int(p["WardPart"]),factor=current["model_mass_g"]!/(volumes[selected]*density/1000),models=volumes.map{$0*density/1000*factor},selectedHeight=heights[selected]
        let skirts=zip(volumes,heights).map{current["skirt_mass_g"]!*($0/$1)/(volumes[selected]/selectedHeight)}
        var printing=0.0,skirt=0.0,travel=0.0
        for q in segments where q[9]>0 {let seconds=distance3(SlicePoint(q[0],q[1],q[2]),SlicePoint(q[3],q[4],q[5]))/q[9];if q[6]==4 {travel+=seconds}else if q[6]==0 {skirt+=seconds}else{printing+=seconds}}
        let times=heights.indices.map{printing*pathLengths[$0]/pathLengths[selected]+travel+skirt*(volumes[$0]/heights[$0])/(volumes[selected]/selectedHeight)}
        return ["motion_minutes":rounded(times.reduce(0,+)/60,1),"parts_motion_minutes":times.map{rounded($0/60,1)},"time_scope":"六件指令运动用时预估；不含预热、调平、加减速、冷却和换件","mass_g":rounded(models.reduce(0,+)+skirts.reduce(0,+)+6*extra,1),"part_count":6,"parts_g":zip(models,skirts).map{rounded($0+$1+extra,1)},"scope":"①至⑥；不含⑦挂衣梁、定位套和管材","method":"轮廓积分快速预估；按当前件出料校准；额外耗料按每件计入","estimated":true]
    }
}
