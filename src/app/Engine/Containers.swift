import Foundation

extension SliceGeometry {
    static func bottleCapacity(_ p:SliceParameters)->Double {
        let bottom=p["H0"]+(p["B"]-1)*p["BH"],height=p["BottleBody"]+p["BottleShoulder"]+p["BottleNeck"],n=10000,dz=(height-bottom)/Double(n)
        return (0..<n).reduce(0){$0+Double.pi*pow(max(0,bottleRadius(bottom+(Double($1)+0.5)*dz,p)-p["W"]),2)*dz}/1e6
    }
    static func bottleModel(_ values:SliceParameters) throws -> SliceShape {
        var p=values
        guard ["BottleDiameter","BottleBody","BottleShoulder","BottleNeck","BottleBore"].allSatisfy({p[$0].isFinite && p[$0]>0}) else {throw SliceFailure("料瓶尺寸必须是正数。")}
        p.set(["CH":p["BottleBody"]+p["BottleShoulder"]+p["BottleNeck"],"Dout":p["BottleDiameter"],"HasBottom":1,"BottomKind":"Solid","EF":0,"EFTable":"","EdgeCalibrationEnabled":false,"AlignLeft":true]);p=try validate(p)
        guard p["BottleBore"]+2*p["W"]<p["BottleDiameter"] else {throw SliceFailure("瓶身外径须大于瓶口外径。")}
        guard p["BottleBody"]>p["H0"]+(p["B"]-1)*p["BH"]+p["H"] else {throw SliceFailure("直身高度不足以容纳封底与墙体。")}
        guard p["BottleNeck"]>=2*p["H"] else {throw SliceFailure("直口高度至少需要两圈。")}
        var model=try circularModel(p)
        model.info+=String(format:"\n10 L 颗粒料瓶：大底贴平台，单墙连续升Z，使用时倒置。名义内部容积 %.2f L（按线宽内缩估算，不代表装料公斤数）。\n封底 %.2f mm；收口搭接已作几何检查，实际成形、气密及承载待试印。",bottleCapacity(p),p["H0"]+(p["B"]-1)*p["BH"])
        return model
    }
    static func hopperCapacity(_ height:Double,_ width:Double) throws -> Double {
        guard height.isFinite,(220...990).contains(height) else {throw SliceFailure("料桶总高请输入 220–990 mm；下端 194.7 mm 固定。")}
        guard width.isFinite,width>0,width<32 else {throw SliceFailure("线宽必须大于 0 且小于 32 mm，保持出料口贯通。")}
        var volume=Double.pi*pow(105-width,2)*(height-194.7)
        for (a,b) in [(0.0,10.0),(10,150),(150,160),(160,180.7),(180.7,194.7)] {let mid=(a+b)/2,half=(b-a)/2;for (x,w) in [(-sqrt(3.0/5),5.0/9),(0,8.0/9),(sqrt(3.0/5),5.0/9)] {volume+=half*w*Double.pi*pow(hopperLowerRadius(mid+half*x)-width,2)}}
        return volume/1e6
    }
    static func hopperReport(_ p:SliceParameters,density:Double) throws -> [String:Any] {
        let volume=try hopperCapacity(p["HopperHeight"],p["W"]),mode=p["HopperDensityMode"],fill=p["HopperFillPercent"],packing=p["HopperPackingPercent"];var bulk=p["HopperBulkDensity"]
        guard density.isFinite,(0.01...30).contains(density) else {throw SliceFailure("材料本体密度请输入 0.01–30 g/cm³。")}
        guard mode==0 || mode==1 else {throw SliceFailure("装料密度方式无效。")}
        guard fill.isFinite,fill>0,fill<=100 else {throw SliceFailure("装满比例请输入大于 0 且不超过 100%。")}
        if mode==0 {guard packing.isFinite,packing>0,packing<=100 else {throw SliceFailure("颗粒占比请输入大于 0 且不超过 100%。")};bulk=density*packing/100}else{guard bulk.isFinite,bulk>0,bulk<=30 else {throw SliceFailure("实测堆积密度请输入大于 0 且不超过 30 kg/L。")}}
        let usable=volume*fill/100
        return ["capacity_litres":volume,"usable_litres":usable,"estimated_load_kg":usable*bulk,"bulk_density_kg_l":bulk,"solid_density_g_cm3":density,"density_basis":mode==1 ? "measured_bulk":"assumed_packing","fill_percent":fill,"packing_percent":mode==0 ? packing as Any:NSNull(),"total_height_mm":p["HopperHeight"],"body_height_mm":p["HopperHeight"]-194.7,"fixed_lower_height_mm":194.7,"outer_diameter_mm":210.0]
    }
    static func hopperModel(_ values:SliceParameters) throws -> SliceShape {
        var p=values;let capacity=try hopperCapacity(p["HopperHeight"],p["W"])
        p.set(["CH":p["HopperHeight"],"Dout":210.0,"HasBottom":0,"EdgeCalibrationEnabled":false]);if !p.flag("EFEnabled",fallback:true) {p.set(["EF":0,"EFTable":""])};p=try validate(p)
        guard p["CH"]-194.7>=p["H0"]+p["H"] else {throw SliceFailure("直筒段需容纳首圈及至少一整圈墙体。")}
        var model=try circularModel(p)
        model.info+=String(format:"\nØ210 可调高料桶：总高 %.3f mm，直筒 %.3f mm；锥段160 + 接口34.7 mm固定。大口贴平台，上下贯通，不封底、不含顶盖。内部几何容积 %.4f L；非打印用料体积。",p["CH"],p["CH"]-194.7,capacity);return model
    }
}
