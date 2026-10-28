import Foundation

extension SliceGeometry {
    static func wardrobeLayout(_ p:SliceParameters) throws -> Int {
        guard [0.0,1.0,2.0].contains(p["WardLayout"]) else {throw SliceFailure("挂衣体方案需选择原六件、独立挂衣矮梁或六件框架。")};return Int(p["WardLayout"])
    }
    static func frameDimensions(_ p:SliceParameters) throws -> [String:Double] {
        let total=p["WardHeight"],b=p["WardBeam"],lower=p.values["WardLowerHeight"]==nil ? 730:p["WardLowerHeight"],upper=total-2*b-lower,topR=p.values["WardTopRadius"]==nil ? 100:p["WardTopRadius"],bottomR=p["WardRadius"]
        guard [total,b,lower,upper,topR,bottomR].allSatisfy(\.isFinite) else {throw SliceFailure("六件框架的尺寸必须为有限数值。")}
        guard b>=60,b<total/2 else {throw SliceFailure("上下梁高度超出框架可用范围。")}
        guard topR>=30,topR<=p["WardOpening"]/2 else {throw SliceFailure("顶部圆角超出开孔可用范围。")}
        guard lower>bottomR,upper>topR else {throw SliceFailure("上下立边高度必须分别大于对应圆角，保证中部拼缝为等截面。")}
        guard max(b,lower,upper)<=990 else {throw SliceFailure("框架单件打印高度需不超过990 mm，以适配1000 mm高的打印空间。")}
        return ["lower_height":lower,"upper_height":upper,"split_z":b+lower,"bottom_radius":bottomR,"top_radius":topR,"opening_height":total-2*b]
    }
    static func hangingDimensions(_ p:SliceParameters) throws -> [String:Double] {
        let b=p["WardBeam"],total=p["WardHeight"],rail=p.values["WardRailHeight"]==nil ? 40:p["WardRailHeight"],gap=p.values["WardHemGap"]==nil ? 100:p["WardHemGap"]
        guard (60...120).contains(gap) else {throw SliceFailure("本方案衣摆余量需为60–120 mm。")}
        guard (20...100).contains(rail) else {throw SliceFailure("独立挂衣矮梁高度需为20–100 mm。")}
        let top=b+gap+1200+200,headroom=total-b-top,opening=top-rail-b
        guard headroom>=80 else {throw SliceFailure("挂衣梁上方净空不足80 mm，请减小上下梁高度或增大整体高度。")}
        guard opening>2*p["WardRadius"] else {throw SliceFailure("主开孔不足以容纳圆角。")}
        return ["rail_top":top,"rail_bottom":top-rail,"rail_height":rail,"hem_gap":gap,"hem_z":b+gap,"headroom":headroom,"opening_height":opening,"post_height":opening/2]
    }
    static func wardrobePrintHeight(_ p:SliceParameters) throws -> Double {
        let part=Int(p["WardPart"]),layout=try wardrobeLayout(p)
        if layout==2 {let d=try frameDimensions(p);guard (0..<6).contains(part),Double(part)==p["WardPart"] else {throw SliceFailure("六件框架请选择①至⑥。")};return [0,5].contains(part) ? p["WardBeam"]:d[[1,2].contains(part) ? "lower_height":"upper_height"]!}
        if layout==0 {return [0,5].contains(part) ? p["WardBeam"]:p["WardHeight"]/2-p["WardBeam"]}
        let d=try hangingDimensions(p)
        switch part {case 0,8:return p["WardBeam"];case 5:return d["rail_height"]!;case 6,7:return d["headroom"]!;case 1,2,3,4:return d["post_height"]!;default:throw SliceFailure("独立挂衣梁方案需选择0–8号分件。")}
    }
}
