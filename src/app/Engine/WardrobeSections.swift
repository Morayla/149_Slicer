import Foundation

final class WardrobeSliceSections {
    typealias G=SliceGeometry
    struct Node {let kind:Int;let u:Double}
    let reference:WardrobeReference
    var p:SliceParameters
    var w=0.0,half=0.0,pad=0.0,B=0.0,R=0.0,H=0.0,need=0.0,hole=0.0,clearance=0.0,bore=0.0,r=0.0,effective=0.0,L=0.0,rotation=0.0,maxEnvelope=0.0,measuredBore=0.0,coilOuterRadius=120.0
    var part=0,side=0,count=450,caps=20,partCount=6
    var upper=false,isBeam=false,isTopLink=false,constantSection=false,quarter=true
    var center=SlicePoint.zero,offset=SlicePoint.zero,pipePrint=SlicePoint.zero
    var spine=[SlicePoint](),arc=[Double](),nodes=[Node](),bounds=[Double](),collarCenters=[SlicePoint]()
    var dims=[String:Double](),openingHeight=0.0,assemblyStart=0.0,assemblyEnd=0.0

    private init(quarter p:SliceParameters,reference:WardrobeReference) throws {
        self.p=p;self.reference=reference;w=p["W"];half=(w+p["WardLaneGap"])/2;pad=half+w/2
        B=p["WardBeam"];R=p["WardRadius"];H=p["WardHeight"]/2;part=Int(p["WardPart"]);side=part%2;upper=part>=2
        need=p["WardCount"]*p["WardPitch"]+2*p["WardEndSpace"];hole=p["WardOpening"];clearance=p["WardClearance"]
        guard Double(part)==p["WardPart"],(0..<4).contains(part) else {throw SliceFailure("分件需选择左下、右下、左上或右上。")}
        guard (1000...1900).contains(p["WardHeight"]) else {throw SliceFailure("整体高度需为 1000–1900 mm。")}
        guard B>=60,B<H-100 else {throw SliceFailure("上下梁高度超出可用范围。")}
        guard R>=30,R<=min(hole/2,H-B) else {throw SliceFailure("圆角半径超出开孔尺寸。")}
        guard (1...20).contains(p["WardCount"]),p["WardCount"].rounded(.towardZero)==p["WardCount"] else {throw SliceFailure("挂衣数量需为 1–20 的整数。")}
        guard (20...100).contains(p["WardPitch"]),p["WardEndSpace"]>=0 else {throw SliceFailure("挂衣间距或两端余量无效。")}
        guard (3...9).contains(w),(0.5...4).contains(p["WardLaneGap"]) else {throw SliceFailure("本造型线宽需为 3–9 mm，双墙净隙需为 0.5–4 mm。")}
        guard (5...35).contains(p["WardPipeD"]),(0.2...3).contains(clearance) else {throw SliceFailure("连接柱直径或装配余量超出可用范围。")}
        bore=p["WardPipeD"]+clearance;r=bore/2+pad+0.15
        let core=p["WardCoreMode"]
        if core==2 || core==3 {let coreBore=p.values["WardCoreBore"]==nil ? 30:p["WardCoreBore"];guard bore<=coreBore,coreBore<=50 else {throw SliceFailure("卷芯内径需不小于管径加装配余量，且不大于50 mm。")};r=coreBore/2+pad+0.15}
        let below=200-B,intrusion=R-sqrt(max(0,R*R-pow(R-min(R,max(0,below)),2)));effective=hole-2*intrusion
        guard below>=0,effective>=need else {throw SliceFailure(String(format:"当前圆角后的有效挂衣宽度不足：需 %.0f mm，现有 %.0f mm；请增大开孔宽度或减小梁高。",need,effective))}
        guard p["WardHeight"]-200-1200>=B+50 else {throw SliceFailure("1200 mm 长衣在开孔底部的余量不足 50 mm。")}
        let original=reference.points;center=reference.centers[side]
        var halfpath=side==0 ? Array(original[1600..<2400]):Array(original[2399..<original.count-1600].reversed())
        let reduction=p["WardCurlReduction"]
        guard reduction.isFinite,(0...90).contains(reduction) else {throw SliceFailure("螺旋减卷角度需为0–90度。")}
        guard [0.0,1.0,2.0,3.0].contains(core) else {throw SliceFailure("卷芯方式无效。")}
        var coil:[SlicePoint]
        if core==3 {
            coilOuterRadius=try reference.plantOuterRadius(w,p["WardLaneGap"],p.values["WardCoreBore"]==nil ? 30:p["WardCoreBore"],p["WardTipClearance"])
            coil=try G.plantCoil(r,coilOuterRadius);halfpath=try reference.plantConnector(r,coilOuterRadius).0
            if side != 0 {let sum=reference.centers[0]+reference.centers[1];halfpath=halfpath.map{sum-$0}}
        }else if core==2 {coil=G.tightCoil(r,reduction)}else if core==1 {coil=G.naturalCoil(reduction)}else{
            let outerSpan=2*Double.pi-2*reduction*Double.pi/180,blendSpan=Double.pi/2+reduction*Double.pi/180,a=(120.0-24)/(2.5*Double.pi)
            coil=(0...320).map{i in let t=outerSpan*Double(i)/320,r=120-a*t,angle=Double.pi+t;return SlicePoint(r*cos(angle),r*sin(angle),0)}
            let r0=120-a*outerSpan
            for i in 1...100 {let u=Double(i)/100,radius=(2*pow(u,3)-3*u*u+1)*r0+(pow(u,3)-2*u*u+u)*(-a*blendSpan)+(-2*pow(u,3)+3*u*u)*r,angle=Double.pi+outerSpan+blendSpan*u;coil.append(SlicePoint(radius*cos(angle),radius*sin(angle),0))}
            for i in 1...200 {let angle=Double.pi+outerSpan+blendSpan+270*Double.pi/180*Double(i)/200;coil.append(SlicePoint(r*cos(angle),r*sin(angle),0))}
        }
        let sign=side==0 ? 1.0:-1.0;coil=coil.map{center+sign*$0}
        spine=G.resample(Array(coil.reversed())+halfpath.dropFirst(),step:1.5);rebuildArc()
        guard hole/2+pad<=L-arc[G.resample(Array(coil.reversed()),step:1.5).count-1]-15 else {throw SliceFailure("开孔过宽，会进入端部螺旋，请减小宽度。")}
        count=450;caps=core==3 ? 80:20;rebuildNodes();fitPlacement(steps:360,opened:false)
        pipePrint=transform(center);maxEnvelope=bounds.max()!+2*(10+w)
        guard maxEnvelope<=980 else {throw SliceFailure("含裙边的分件超出 980 mm 规划包络。")}
        for (z,opened) in [(0.0,false),(B,true),(B+10,true),(B+R/2,true),(B+R,true),(H,true)] {
            let poly=Array(loop(z,opened).dropLast());try G.checkSpacing(poly,width:w)
            measuredBore=measureBore(poly,pipePrint)
            guard measuredBore>=bore-0.01 else {throw SliceFailure(String(format:"连接柱孔径不足：%.3f mm。",measuredBore))}
        }
    }
    private func rebuildArc() {arc=[0];for i in 1..<spine.count {arc.append(arc.last!+G.xyLength(spine[i-1],spine[i]))};L=arc.last!}
    private func rebuildNodes() {
        nodes=(0...count).map{Node(kind:0,u:Double($0)/Double(count))};nodes += (1..<caps).map{Node(kind:1,u:Double($0)/Double(caps))}
        nodes += (0...count).reversed().map{Node(kind:2,u:Double($0)/Double(count))};nodes += (1..<caps).map{Node(kind:3,u:Double($0)/Double(caps))};nodes.append(nodes[0])
    }
    private func fitPlacement(steps:Int,opened:Bool) {
        rotation=0;offset = .zero;let raw=loop(0,opened)
        var score=Double.infinity,bestAngle=0.0,best=[Double]()
        for i in 0...steps {
            let angle=Double.pi*Double(i)/Double(2*steps),c=cos(angle),s=sin(angle);var minX=Double.infinity,minY=Double.infinity,maxX = -Double.infinity,maxY = -Double.infinity
            for q in raw {let x=q.x*c-q.y*s,y=q.x*s+q.y*c;minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)}
            let candidate=max(maxX-minX,maxY-minY);if candidate<score {score=candidate;bestAngle=angle;best=[minX,minY,maxX,maxY]}
        }
        rotation=bestAngle;offset=SlicePoint(-(best[0]+best[2])/2,-(best[1]+best[3])/2,0);bounds=[best[2]-best[0]+w,best[3]-best[1]+w]
    }
    private func measureBore(_ poly:[SlicePoint],_ center:SlicePoint)->Double {2*(poly.indices.map{G.pointDistance(center,poly[$0],poly[($0+1)%poly.count])}.min()!-w/2)}
    static func six(_ p:SliceParameters,reference:WardrobeReference) throws -> WardrobeSliceSections {
        let part=Int(p["WardPart"])
        guard Double(part)==p["WardPart"],(0..<6).contains(part) else {throw SliceFailure("分件需为底梁、左下段、右下段、左上段、右上段或顶梁。")}
        var proxy=p;proxy["WardPart"]=Double([0,0,1,2,3,2][part]);let sec=try WardrobeSliceSections(quarter:proxy,reference:reference)
        sec.p=p;sec.part=part;sec.isBeam=[0,5].contains(part);sec.H=sec.isBeam ? p["WardBeam"]:p["WardHeight"]/2-p["WardBeam"];sec.B=0;sec.collarCenters=[sec.center];sec.quarter=false
        if sec.isBeam {proxy["WardPart"]=part==0 ? 1:3;let other=try WardrobeSliceSections(quarter:proxy,reference:reference);sec.spine += other.spine.dropLast().reversed();sec.rebuildArc();sec.collarCenters.append(other.center)}
        sec.count=sec.isBeam ? 900:450;sec.rebuildNodes();sec.fitPlacement(steps:720,opened:true)
        sec.maxEnvelope=sec.bounds.max()!+2*(10+sec.w)
        guard sec.maxEnvelope<=995 else {throw SliceFailure("分件含裙边超出 995 mm 包络，请减小线宽或裙边间距。")}
        sec.pipePrint=sec.transform(sec.center);sec.measuredBore = .infinity
        for z in sec.isBeam ? [0,sec.H]:[0,10,100,200,sec.H] {
            let poly=Array(sec.loop(z,true).dropLast());try G.checkSpacing(poly,width:sec.w)
            for center in sec.collarCenters {sec.measuredBore=min(sec.measuredBore,sec.measureBore(poly,sec.transform(center)))}
        }
        guard sec.measuredBore>=sec.bore-0.01 else {throw SliceFailure("卷芯的最小孔径不足。")};return sec
    }
    static func make(_ p:SliceParameters,reference:WardrobeReference) throws -> WardrobeSliceSections {
        let layout=try G.wardrobeLayout(p),part=Int(p["WardPart"])
        if layout==0 {let sec=try six(p,reference:reference);sec.partCount=6;sec.constantSection=sec.isBeam;sec.openingHeight=p["WardHeight"]-2*p["WardBeam"];return sec}
        if layout==2 {
            let dims=try G.frameDimensions(p),height=try G.wardrobePrintHeight(p);var proxy=p;proxy["WardRadius"]=dims[[3,4,5].contains(part) ? "top_radius":"bottom_radius"]!
            let sec=try six(proxy,reference:reference);sec.p=p;sec.dims=dims;sec.H=height;sec.partCount=6;sec.constantSection=sec.isBeam;sec.openingHeight=dims["opening_height"]!
            sec.assemblyStart=part==0 ? 0:([1,2].contains(part) ? p["WardBeam"]:([3,4].contains(part) ? dims["split_z"]!:p["WardHeight"]-p["WardBeam"]));sec.assemblyEnd=sec.assemblyStart+height;return sec
        }
        guard Double(part)==p["WardPart"],(0..<9).contains(part) else {throw SliceFailure("独立挂衣梁方案需选择九个分件之一。")}
        let dims=try G.hangingDimensions(p);var proxy=p;proxy.set(["WardPart":[0,1,2,3,4,0,1,2,5][part],"WardHeight":2*p["WardBeam"]+dims["opening_height"]!])
        let sec=try six(proxy,reference:reference);sec.p=p;sec.part=part;sec.dims=dims;sec.H=try G.wardrobePrintHeight(p);sec.partCount=9;sec.isTopLink=[6,7].contains(part);sec.constantSection=sec.isBeam || sec.isTopLink;sec.openingHeight=dims["opening_height"]!
        switch part {case 0:sec.assemblyStart=0;case 1,2:sec.assemblyStart=p["WardBeam"];case 3,4:sec.assemblyStart=p["WardBeam"]+dims["post_height"]!;case 5:sec.assemblyStart=dims["rail_bottom"]!;case 6,7:sec.assemblyStart=dims["rail_top"]!;default:sec.assemblyStart=p["WardHeight"]-p["WardBeam"]}
        let below=max(0,min(sec.R,200-dims["rail_height"]!)),intrusion=sec.R-sqrt(max(0,sec.R*sec.R-pow(sec.R-below,2)));sec.effective=sec.hole-2*intrusion
        guard sec.effective>=sec.need else {throw SliceFailure("独立挂衣梁下方的有效宽度不足。")}
        let poly=Array(sec.loop(0,true).dropLast());try G.checkSpacing(poly,width:sec.w)
        sec.bounds=[poly.map{$0.x}.max()!-poly.map{$0.x}.min()!+sec.w,poly.map{$0.y}.max()!-poly.map{$0.y}.min()!+sec.w];sec.maxEnvelope=sec.bounds.max()!+2*(10+sec.w)
        sec.measuredBore=sec.collarCenters.map{sec.measureBore(poly,sec.transform($0))}.min()!
        guard sec.measuredBore>=sec.bore-0.01 else {throw SliceFailure("连接柱孔径不足。")};return sec
    }
    func endpoint(_ z:Double,_ opened:Bool)->Double {
        if isTopLink {return L-hole/2-pad}
        if !quarter {if isBeam {return L};let d=max(0,min(R,z)),inset=R-sqrt(max(0,R*R-pow(R-d,2)));return L-hole/2+inset-pad}
        if !opened {return L-pad-0.25}
        let d=max(0,min(R,z-B)),inset=R-sqrt(max(0,R*R-pow(R-d,2)));return L-hole/2+inset-pad
    }
    func frame(_ s:Double)->(SlicePoint,SlicePoint,SlicePoint) {
        let j=min(spine.count-2,max(0,G.upperBound(arc,s)-1)),u=(s-arc[j])/(arc[j+1]-arc[j]),a=spine[j],b=spine[j+1],q=a+(b-a)*u
        func tangent(_ i:Int)->SlicePoint {
            if p["WardCoreMode"]==3 {
                if i==0 {return G.unit2(SlicePoint(spine[0].y-center.y,center.x-spine[0].x,0))}
                if i==spine.count-1 && isBeam {let c=collarCenters.last!;return G.unit2(SlicePoint(c.y-spine.last!.y,spine.last!.x-c.x,0))}
            }
            return G.unit2(spine[min(i+1,spine.count-1)]-spine[max(0,i-1)])
        }
        let ta=tangent(j),tb=tangent(j+1),t=G.unit2(ta+(tb-ta)*u);return (q,t,SlicePoint(-t.y,t.x,0))
    }
    func transform(_ q:SlicePoint)->SlicePoint {let x=upper ? -q.x:q.x,c=cos(rotation),s=sin(rotation);return SlicePoint(x*c-q.y*s+offset.x,x*s+q.y*c+offset.y,0)}
    func at(_ node:Node,_ z:Double,_ opened:Bool)->SlicePoint {
        let kind=node.kind,u=node.u,end=endpoint(z,opened),(q,t,n)=frame(end*((kind==0 || kind==2) ? u:(kind==1 ? 1:0)))
        if p["WardCoreMode"]==3 && (kind==3 || (kind==1 && isBeam)) {
            let controls=G.returnControls(r,half),x=G.quinticValue(controls.map{$0.x},u),y=G.quinticValue(controls.map{$0.y},u),sign=kind==3 ? 1.0:-1.0
            var point=transform(q+sign*(x*n+y*t));point.z=z;return point
        }
        let v:SlicePoint
        if kind==0 {v=n}else if kind==2 {v = -n}else{let a=Double.pi*u,sign=kind==1 ? 1.0:-1.0;v=sign*(cos(a)*n+sin(a)*t)}
        var point=transform(q+half*v);point.z=z;return point
    }
    func loop(_ z:Double,_ opened:Bool)->[SlicePoint] {nodes.map{at($0,z,opened)}}
}

extension WardrobeSliceSections {
    static func quarterLengths(_ values:SliceParameters,reference:WardrobeReference) throws -> [Double] {
        try (0...1).map {i in var p=values;p["WardPart"]=Double(i);return try WardrobeSliceSections(quarter:p,reference:reference).L}
    }
}
