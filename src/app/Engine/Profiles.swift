import Foundation

extension SliceGeometry {
    struct RadialProfile {
        let total:Double
        let growth:Int
        let peakPitch:Double
        let ease:Double
        let radius:(Double)->Double
        let derivative:(Double)->Double
        var width:((Double)->Double)?
    }
    static func radialProfile(inner:Double,outer:Double,pitch:Double,ease:Double,open:Bool=false,entry:SliceParameters?=nil) throws -> RadialProfile {
        let span=outer-inner
        if span<=1e-8 {
            if open || entry != nil {throw SliceFailure("内圈起步需要留出向外螺旋的空间。")}
            return RadialProfile(total:1,growth:0,peakPitch:0,ease:ease,radius:{_ in inner},derivative:{_ in 0})
        }
        if let p=entry {
            let start=p["InnerEaseTurns"],widthTurns=p["InnerWidthTurns"],initial=p["InnerStartW"],nominal=p["W"]
            let growth=max(1,Int(ceil(span/pitch+(start+ease)/2)),Int(ceil(start+ease)),Int(ceil(widthTurns+ease)))
            let count=Double(growth),speed=span/(count-(start+ease)/2)
            func width(_ t:Double)->Double {initial+(nominal-initial)*smooth(t/widthTurns)}
            func travelled(_ t:Double)->Double {
                if t<=0 {return 0};if t>=count {return count-(start+ease)/2}
                if t<start {return start*integralSmooth(t/start)}
                if t>count-ease {return count-(start+ease)/2-ease*integralSmooth((count-t)/ease)}
                return t-start/2
            }
            return RadialProfile(total:count+1,growth:growth,peakPitch:speed,ease:ease,
                radius:{inner+speed*travelled($0)+(width($0)-nominal)/2},
                derivative:{t in let u=min(1,max(0,t/widthTurns));return speed*min(smooth(t/start),smooth((count-t)/ease))+(nominal-initial)*3*u*(1-u)/widthTurns},width:width)
        }
        if open {
            let growth=max(1,Int(ceil(span/pitch+ease/2))),count=Double(growth),speed=span/(count-ease/2)
            func travelled(_ t:Double)->Double {
                if t<=0 {return 0};if t>=count {return count-ease/2};if t<=count-ease {return t}
                return count-ease/2-ease*integralSmooth((count-t)/ease)
            }
            return RadialProfile(total:count+1,growth:growth,peakPitch:speed,ease:ease,
                radius:{inner+speed*travelled($0)},derivative:{$0<count ? speed*smooth((count-$0)/ease):0})
        }
        let growth=max(1,Int(ceil(span/pitch+ease))),count=Double(growth),speed=span/(count-ease)
        func travelled(_ x:Double)->Double {
            if x<=0 {return 0};if x>=count {return count-ease}
            if x<ease {return ease*integralSmooth(x/ease)}
            if x>count-ease {return count-ease-ease*integralSmooth((count-x)/ease)}
            return x-ease/2
        }
        return RadialProfile(total:count+2,growth:growth,peakPitch:speed,ease:ease,
            radius:{inner+speed*travelled($0-1)},derivative:{t in let x=t-1;return x<=0 || x>=count ? 0:speed*min(smooth(x/ease),smooth((count-x)/ease))})
    }

    static func efProfile(_ p:inout SliceParameters) throws -> (Double)->Double {
        let n=Int(p["EFLayers"])
        let rows=p.text("EFTable").replacingOccurrences(of:";",with:"\n").components(separatedBy:.newlines)
            .map{String($0.split(separator:"#",omittingEmptySubsequences:false)[0]).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
        if rows.isEmpty {
            p.values["EFTableMode"]="AUTO"
            p.values["EFTurnPercent"]=(0...n).map{100*(1-smooth(Double($0)/Double(n)))}
            return {1-smooth($0/Double(n))}
        }
        let regex=try NSRegularExpression(pattern:#"^([0-9]+)\s*[:=,]\s*([+\-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))\s*%?$"#)
        var table=[Int:Double]()
        for line in rows {
            let text=line as NSString
            guard let match=regex.firstMatch(in:line,range:NSRange(location:0,length:text.length)),
                  let turn=Int(text.substring(with:match.range(at:1))),let percent=Double(text.substring(with:match.range(at:2))) else {
                throw SliceFailure("EFTable row must be TURN:PERCENT, e.g. 8:20")
            }
            if table[turn] != nil {throw SliceFailure("Duplicate EFTable turn \(turn)")}
            if turn>n {throw SliceFailure("EFTable turn exceeds EFLayers: \(turn)")}
            if percent<0 || percent>100 {throw SliceFailure("EFTable percentages must be 0..100")}
            table[turn]=percent
        }
        if let first=table[0],first != 100 {throw SliceFailure("EFTable turn 0 must be 100%")}
        if let last=table[n],last != 0 {throw SliceFailure("EFTable final turn must be 0%")}
        table[0]=100;table[n]=0
        let missing=(1..<n).filter{table[$0]==nil}
        if !missing.isEmpty {throw SliceFailure("EFTable missing turns: "+missing.map(String.init).joined(separator:","))}
        let y=(0...n).map{table[$0]!/100}
        if (1...n).contains(where:{y[$0-1]<y[$0]}) {throw SliceFailure("EFTable must decrease or stay equal as turn number increases")}
        let delta=(1...n).map{y[$0]-y[$0-1]}
        var slopes=[0.0]
        for i in 1..<delta.count {let a=delta[i-1],b=delta[i];slopes.append(a*b>0 ? 2*a*b/(a+b):0)}
        slopes.append(0)
        for i in delta.indices {
            let bound = -3*delta[i],total = -slopes[i]-slopes[i+1]
            if total>bound && total>0 {let scale=bound/total;slopes[i]*=scale;slopes[i+1]*=scale}
        }
        p.values["EFTableMode"]="PER_TURN";p.values["EFTurnPercent"]=y.map{100*$0}
        let tangent=slopes
        return {turn in
            if turn<=0 {return 1};if turn>=Double(n) {return 0}
            let i=Int(floor(turn)),v=turn-Double(i),v2=v*v,v3=v2*v
            return (2*v3-3*v2+1)*y[i]+(v3-2*v2+v)*tangent[i]+(-2*v3+3*v2)*y[i+1]+(v3-v2)*tangent[i+1]
        }
    }

    static func validate(_ input:SliceParameters) throws -> SliceParameters {
        var p=input
        if p.values.keys.contains(where:{$0.hasPrefix("Outer")}) {throw SliceFailure("本版本不支持首层外缘局部尺寸校准参数。")}
        let modes=["Cylinder","Ellipse","Cone","Triple","TripleVase","DoubleScroll","Imported","NonplanarCylinder","Crescent","SingleBud","CornerPipe","EggScroll","Wardrobe","TravelTest","Fern1060","Fern1060E","PipeScroll","PelletBottle","Hopper"]
        guard modes.contains(p.text("SourceMode")) else {throw SliceFailure("不支持的造型类型。")}
        let textFields:Set<String>=["SourceMode","EFTable","BottomKind","BottomPattern","FillAngles","ImportFile"]
        for (key,value) in p.values where !textFields.contains(key) {
            guard let number=(value as? NSNumber)?.doubleValue ?? Double(value as? String ?? ""),number.isFinite else {throw SliceFailure(key+" 必须是有限数值。")}
            p[key]=number
        }
        guard ["Annular","Solid"].contains(p.text("BottomKind",fallback:"Annular")),["Spiral","Monotonic","Zigzag"].contains(p.text("BottomPattern",fallback:"Spiral")) else {throw SliceFailure("底部类型或填充方式无效。")}
        for key in ["B","N","EFLayers","HasBottom","InnerOpen","InnerEntry"] where p[key].rounded(.towardZero) != p[key] {throw SliceFailure(key+" 必须为整数。")}
        for key in ["W","WB","H","H0","BH","CH","Dout","Din","Tolerance","BlendAngle"] where p[key]<=0 {throw SliceFailure(key+" 必须大于 0。")}
        guard (1...200).contains(p["EFLayers"]) else {throw SliceFailure("EF 补偿圈数必须在 1–200 之间。")}
        guard p["EF"]>=0 else {throw SliceFailure("EF 补偿量不能小于 0。")}
        guard [0.0,1.0].contains(p["HasBottom"]),[0.0,1.0].contains(p["InnerOpen"]) else {throw SliceFailure("底部 / 内圈模式无效。")}
        if p.flag("HasBottom") && !(1...20).contains(p["B"]) {throw SliceFailure("底部层数必须在 1–20 之间。")}
        if p["H"]>p["W"] || p["H0"]>(p.flag("HasBottom") ? p["WB"]:p["W"]) || p["BH"]>p["WB"] {throw SliceFailure("层高不能超过对应线宽。")}
        guard (10...360).contains(p["BlendAngle"]) else {throw SliceFailure("底部过渡角必须在 10–360° 之间。")}
        guard p["N"]==0 || (64...2000).contains(p["N"]) else {throw SliceFailure("采样数必须为 0（自动）或 64–2000。")}
        guard (0.02...1).contains(p["Tolerance"]) else {throw SliceFailure("精度必须在 0.02–1 mm 之间。")}
        if p.flag("InnerOpen") && p.flag("InnerEntry") && min(p["InnerWidthTurns"],p["InnerEaseTurns"])<=0 {throw SliceFailure("内圈过渡圈数必须大于 0。")}
        if p["EF"]==0 {p.values["EFTable"]=""}
        if p.values["EdgeBulgeIn"]==nil {p["EdgeBulgeIn"]=1.5};if p.values["EdgeDipOut"]==nil {p["EdgeDipOut"]=0.5}
        if p["EdgeBulgeIn"]<0 || p["EdgeDipOut"]<0 {throw SliceFailure("首层外缘校准量不能为负数。")}
        guard [0.0,1.0].contains(p["EdgeCalibrationEnabled"]) else {throw SliceFailure("首层外缘校准开关无效。")}
        p.set(["CX":0.0,"CY":0.0,"PF":1.0,"FM":1.0,"F0":1.0,"F":420.0,"Finish":0,"FinishFlow":0.2])
        return p
    }
}
