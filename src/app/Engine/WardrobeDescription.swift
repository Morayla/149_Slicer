import Foundation

extension SliceGeometry {
    static func wardrobeDescription(_ p:SliceParameters,_ sec:WardrobeSliceSections,height:Double,bedTest:Bool,continuousTest:Bool,testLayers:Int,testPitch:Double,pitchRange:[Double],amount:Double,measured:Bool,offsets:[Double])->String {
        func f(_ value:Double,_ places:Int=0)->String {String(format:"%.*f",places,value)}
        let first=p["H0"],nominal=p["H"],width=p["W"]
        var info:String
        if sec.partCount==9 {
            let names=["底梁","左下段","右下段","左上段（倒置打印）","右上段（倒置打印）","独立挂衣矮梁","左顶部连接段","右顶部连接段","顶梁"],d=sec.dims
            info="螺旋挂衣体 · \(names[sec.part]) / 九件拼接\n总高 \(f(p["WardHeight"])) mm；本件高 \(f(height)) mm，装配高度区间 \(f(sec.assemblyStart))–\(f(sec.assemblyStart+height)) mm。\n挂衣上沿离地 \(f(d["rail_top"]!)) mm；矮梁自身高 \(f(d["rail_height"]!)) mm；上下整梁各 \(f(p["WardBeam"])) mm。\n1200 mm衣长 + 200 mm衣架占高：衣摆离地 \(f(d["hem_z"]!)) mm，距底梁 \(f(d["hem_gap"]!)) mm。\n主孔展开宽 \(f(sec.hole)) × 高 \(f(d["opening_height"]!)) mm，R\(f(sec.R))；肩部净宽 \(f(sec.effective,1)) mm。上方辅助开口净高 \(f(d["headroom"]!)) mm，顶部连接段为等截面。\n本件料道包络 \(f(sec.bounds[0],1)) × \(f(sec.bounds[1],1)) mm；柱体 Ø\(f(p["WardPipeD"],1))，最小配合孔约 Ø\(f(sec.measuredBore,3)) mm。\n矮梁与上下梁使用相同完整S形和两端螺旋，九件分别连续打印、叠装于同两根立柱。\n各件主体一笔连续无中途空移；首层及收口有等高段。矮梁高度是几何设计值，尚未经承重验证；柱体轴向锁定及衣架插配需实物校核。"
        }else if p["WardLayout"]==2 {
            let names=["①底梁","②左下段","③右下段","④左上段（倒置打印）","⑤右上段（倒置打印）","⑥顶梁"],d=sec.dims
            info="螺旋挂衣体 · \(names[sec.part]) / 当前六件框架\n总高 \(f(p["WardHeight"])) mm；本件打印高 \(f(height)) mm，装配区间 \(f(sec.assemblyStart))–\(f(sec.assemblyEnd)) mm。\n装配高度：底梁 \(f(p["WardBeam"])) + 下段 \(f(d["lower_height"]!)) + 上段 \(f(d["upper_height"]!)) + 顶梁 \(f(p["WardBeam"])) mm；中部接缝离地 \(f(d["split_z"]!)) mm。\n直接成孔：展开宽 \(f(sec.hole)) × 高 \(f(d["opening_height"]!)) mm；顶部 R\(f(d["top_radius"]!))，底部 R\(f(d["bottom_radius"]!))。\n本件料道包络 \(f(sec.bounds[0],1)) × \(f(sec.bounds[1],1)) mm；Ø\(f(p["WardPipeD"],1)) 柱体，目标孔径 \(f(sec.bore,2)) mm，几何最小孔径 \(f(sec.measuredBore,3)) mm。\n双墙各 \(f(width,1)) mm、净隙 \(f(p["WardLaneGap"],1)) mm；主体连续升Z、无中途空移，首层及收口有等高段。\n仅更新①至⑥：④⑤保持完整，⑦挂衣梁及其钻孔、连接件未生成。\n两根管轴保持原坐标；上段倒置打印后翻回安装。实物插配、接缝固定和材料承载仍需验证。"
        }else{
            let names=["底梁（整件）","左下段","右下段","左上段（倒置打印）","右上段（倒置打印）","顶梁（整件，倒置安装）"]
            info="螺旋挂衣体 · \(names[sec.part]) / 六件拼接\n总高 \(f(p["WardHeight"])) mm；本件高 \(f(height)) mm；上下整梁各 \(f(p["WardBeam"])) mm，中段分两层。\n直接成孔：展开宽 \(f(sec.hole)) × 高 \(f(p["WardHeight"]-2*p["WardBeam"])) mm，R\(f(sec.R))；按 \(f(p["WardCount"])) 件 × \(f(p["WardPitch"])) mm + 两端各 \(f(p["WardEndSpace"])) mm，需求 \(f(sec.need)) mm，肩部有效宽 \(f(sec.effective,1)) mm。\n卷芯连接柱 Ø\(f(p["WardPipeD"],1)) mm；直径余量 \(f(sec.clearance,1)) mm；当前几何包络最小孔径 \(f(sec.measuredBore,3)) mm。\n分件占地 \(f(sec.bounds[0],1)) × \(f(sec.bounds[1],1)) mm；含 10 mm 裙边间距的包络不超过 \(f(sec.maxEnvelope,1)) mm。\n双墙各 \(f(width,1)) mm、净隙 \(f(p["WardLaneGap"],1)) mm；圆角区自动减小每周上升量。每件一笔闭合连续升 Z，无跨孔挤出、无中途空移。\n装配从下到上：\(f(p["WardBeam"])) + \(f(p["WardHeight"]/2-p["WardBeam"])) + \(f(p["WardHeight"]/2-p["WardBeam"])) + \(f(p["WardBeam"])) mm。上下整梁没有中缝；两根立柱贯穿卷芯并需轴向锁定。\n分件相接的梁面与立柱需机械固定；材料承载、喷嘴实体净空与实际插配仍需样件验证。"
        }
        if bedTest {
            info="全尺寸底梁 · \(testLayers)层平台测试\n保持①底梁原尺寸、原摆放和完整双墙轮廓，不缩小。\n共 \(testLayers) 层等高闭合走线：首层 \(fmt(first)) mm，其后每层 \(fmt(nominal)) mm，总高 \(fmt(height)) mm；无额外顶部整平圈。\n模型包络 \(f(sec.bounds[0],1)) × \(f(sec.bounds[1],1)) × \(fmt(height)) mm。裙边只在第一层先打印。\n用于检查整个平台的占地、首层附着与出料；不是承重或高件稳定性测试。关闭底部测试即可恢复正式分件。"
            if continuousTest {info="全尺寸底梁 · \(testLayers)层连续升 Z 测试\n保持①底梁完整尺寸与正式件起始路径。\n首层等高 \(fmt(first)) mm；其后 \(testLayers-1) 圈连续升 Z，每圈升高 \(f(testPitch,4)) mm，总高 \(f(height,4)) mm。\n保留正式底梁的实际圈距、挤出和 EF 过渡；最后一圈结束即收尾，不额外填平顶部。\n模型包络 \(f(sec.bounds[0],1)) × \(f(sec.bounds[1],1)) mm；裙边仅在首层先打印。\n用于检查首层、连续升 Z 与层间搭接；顶部为螺旋高差，不是装配平面。关闭测试即可恢复正式分件。"}
        }
        if p["WardCoreMode"]==3 {info+="\n确认版绿色轮廓：整段510°四次径向解析螺旋，S形按弧长曲率单调展开；原管轴不移动，原贴墙切点不再保留；最小净空约\(f(sec.measuredBore,2)) mm。独立定位套后装。"}
        if p["WardCoreMode"]==2 {info+="\n小卷芯精确包裹270°，设定内径\(f(p["WardCoreBore"],1)) mm，实际最小净空约\(f(sec.measuredBore,2)) mm；余隙以后装连接件填补。"}
        if p["WardCoreMode"]==1 {info+="\n自然螺旋总转角 \(f(450-p["WardCurlReduction"]))°；不额外拐弯包管。柱周最小径向净余量约 \(f((sec.measuredBore-p["WardPipeD"])/2,1)) mm，须以后装填隙连接件定位；本次不制作该连接件。"}
        if p["WardCoreMode"]==3 && width>6 && p["WardTipClearance"]==0 {info+="\n粗线宽卷尖补偿：外圈半径 \(f(sec.coilOuterRadius,2)) mm；卷尖至相邻回旋边净空按6 mm线宽参考保持，双墙净间隙仍为 \(fmt(p["WardLaneGap"])) mm。"}
        if !bedTest {info+="\n层高策略：\(p["WardLayerMode"]==1 ? "统一":"圆角细层")；主体每圈升高 \(f(pitchRange[0],4))–\(f(pitchRange[1],4)) mm，首层与顶部收口除外。"}
        if amount != 0 && !measured {info+="\n首层几何 EF：沿闭合轮廓内缩 \(fmt(amount)) mm；线宽 \(fmt(width)) mm、单位长度对应挤出截面积保持，挤出按实际路径长度计算。"+(bedTest && !continuousTest ? "第二层恢复原轮廓，接缝处抬 Z 后短距离移位。":"首层后一个连续上升圈平滑恢复原轮廓，之后不再补偿。")}
        if !bedTest || continuousTest {info+="\n起始过渡：第二层开头局部加快升 Z，提前量最多 0.6 mm / 圈距的20%；圈末恢复原高度，下一圈按实际下层重新计算挤出。用于缩短极低流量段，实物效果需三层试打验证。"}
        if !bedTest {info+="\n顶部反向过渡：最后一个上升圈局部延后升 Z（最多 0.6 mm / 圈距的20%），末圈保持设计顶高并按实际间隙补平，将极低流量集中到收尾短段。总高度不增加，未附加打磨余量；顶面实物仍需检验。"}
        if p["WardCoreMode"] != 3 {info+="\n当前卷芯模式的减卷参数 \(f(p["WardCurlReduction"]))°；连接柱轴线与外侧定位基准保持不变。"}
        if measured {info+="\n实测逐层 EF（从各件首层起，mm）："+offsets.map{fmt($0)}.joined(separator:", ")+"；第\(offsets.count+1)层起为0，层间平滑过渡。"}
        if p["WardTipClearance"]>0 {info+="\n卷尖至相邻外圈净空锁定为 \(f(p["WardTipClearance"],3)) mm，独立于双墙净间隙。"}
        return info
    }
}
