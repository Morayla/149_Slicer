import Foundation

extension SliceGeometry {
    static func makeShape(_ values:SliceParameters,resources:URL,stepHelper:URL?=nil,wardrobeReference:WardrobeReference?=nil) throws -> SliceShape {
        var p=values;let mode=p.text("SourceMode",fallback:"Cylinder")
        switch mode {
        case "Hopper":return try hopperModel(p)
        case "PelletBottle":return try bottleModel(p)
        case "Fern1060","Fern1060E":
            p.set(["CH":p["FernDepth"],"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false]);return try fernModel(validate(p),resources:resources)
        case "PipeScroll":
            p.set(["CH":p["PipeScrollHeight"],"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false,"DoubleLaneGap":3]);return try pipeModel(validate(p),resources:resources)
        case "TravelTest":
            p.set(["W":8,"H":3.5,"H0":2.5,"CH":2.5+3.5*p["TravelTestRounds"],"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false]);return try travelModel(validate(p))
        case "Wardrobe":
            if p.flag("WardBedTest") {guard [2.0,3.0].contains(p["WardTestLayers"]) else {throw SliceFailure("底部测试层数请选择2层或3层。")};p["WardPart"]=0}
            let height=p.flag("WardBedTest") ? p["H0"]+p["H"]*(p["WardTestLayers"]-1):try wardrobePrintHeight(p)
            p.set(["CH":height,"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false]);return try wardrobeModel(validate(p),reference:wardrobeReference ?? WardrobeReference(resources:resources))
        case "EggScroll":
            p.set(["CH":p["EggHeight"]*80/650,"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false]);return try eggModel(validate(p),resources:resources)
        case "CornerPipe":
            p.set(["CH":p["CornerHeight"],"HasBottom":0,"EF":0,"EFTable":"","EdgeCalibrationEnabled":false]);return try cornerModel(validate(p))
        case "SingleBud":p.set(["CH":p["BudHeight"],"HasBottom":0,"EF":0,"EFTable":""]);return try budModel(validate(p))
        case "Crescent":p.set(["CH":p["CrescentHeight"],"HasBottom":0,"EF":0,"EFTable":""]);return try crescentModel(validate(p))
        case "DoubleScroll":
            p.set(["CH":p["DoubleHeight"],"HasBottom":0]);if p["DoubleLines"]==1 || !p.flag("EFEnabled",fallback:true) {p.set(["EF":0,"EFTable":""])};return try doubleModel(validate(p))
        case "TripleVase":
            p.set(["CH":p["VaseHeight"],"HasBottom":1,"B":p["VaseBaseLayers"],"EF":0,"EFTable":"","BottomKind":"Solid","BottomPattern":"Zigzag"]);return try tripleVaseModel(validate(p))
        default:break
        }
        if !p.flag("EFEnabled",fallback:true) {p.set(["EF":0,"EFTable":""])}
        switch mode {
        case "Ellipse":
            guard ["EllipseMajor","EllipseMinor","EllipseHeight","EllipseRotation"].allSatisfy({p[$0].isFinite}) else {throw SliceFailure("椭圆参数必须为有限数值。")}
            guard p["EllipseMinor"]>0,p["EllipseMinor"]<=p["EllipseMajor"],p["EllipseHeight"]>0 else {throw SliceFailure("椭圆长轴须不小于短轴，两轴和高度均须大于 0。")}
            let inset=max(p["W"],p.flag("HasBottom") ? p["WB"]:0)/2+p["EF"]
            guard inset<p["EllipseMinor"]*p["EllipseMinor"]/(2*p["EllipseMajor"]) else {throw SliceFailure("椭圆过扁，线宽或 EF 内缩会使端部重叠；请增大短轴或减小线宽 / EF。")}
            p.set(["Dout":p["EllipseMajor"],"CH":p["EllipseHeight"]]);return try circularModel(p)
        case "NonplanarCylinder":return try nonplanarModel(p)
        case "Cone":
            p.set(["Dout":p["ConeBottomD"],"CH":p["ConeHeight"]]);guard min(p["ConeBottomD"],p["ConeTopD"])>p["W"] else {throw SliceFailure("锥形上下口径都必须大于线宽；本版支持开口锥形灯罩，不收尖封顶。")};return try circularModel(p)
        case "Triple":p.set(["CH":p["TripleHeight"],"H":p["TriplePitch"],"HasBottom":0,"EF":0,"EFTable":""]);return try tripleModel(validate(p))
        default:return try circularModel(p,stepHelper:stepHelper)
        }
    }
    static func lowerBound(_ values:[Double],_ value:Double)->Int {var low=0,high=values.count;while low<high {let mid=(low+high)/2;if values[mid]<value {low=mid+1}else{high=mid}};return low}
    static func distance3(_ a:SlicePoint,_ b:SlicePoint)->Double {let d=a-b;return hypot(hypot(d.x,d.y),d.z)}
}
