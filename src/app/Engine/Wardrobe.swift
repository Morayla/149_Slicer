import Foundation

extension SliceGeometry {
    static func wardrobeModel(_ values:SliceParameters,reference:WardrobeReference) throws -> SliceShape {
        var p=values;let bedTest=p.flag("WardBedTest");if bedTest {p["WardPart"]=0}
        let sec=try WardrobeSliceSections.make(p,reference:reference),first=p["H0"],nominal=p["H"],width=p["W"],continuousTest=bedTest && p.flag("WardTestContinuous")
        var height=sec.H,testLayers=p.values["WardTestLayers"]==nil ? 2:p["WardTestLayers"],testPitch=nominal
        if bedTest {
            guard testLayers==2 || testLayers==3 else {throw SliceFailure("底部测试层数请选择2层或3层。")}
            height=first+nominal*(testLayers-1)
            if continuousTest {testPitch=(sec.H-first)/ceil((sec.H-first)/nominal-1e-9);height=first+testPitch*(testLayers-1)}
        }
        let measured=p.flag("WardEFMeasured") && p.flag("WardEFEnabled"),offsets=measured ? try measuredWardrobeValues(p):[]
        guard ["WardEFEnabled","WardEFMeasured","WardEFGrouped"].allSatisfy({[0.0,1.0].contains(p[$0])}) else {throw SliceFailure("挂衣体 EF 开关无效。")}
        let amount=measured ? offsets.max()!:(p.flag("WardEFEnabled") ? (p.values["WardEF"]==nil ? 0.2:p["WardEF"]):0)
        guard amount.isFinite,amount>=0 else {throw SliceFailure("挂衣体 EF 内缩量必须为非负有限数值。")}
        var efParameters=p;efParameters.set(["EF":amount,"EFLayers":1,"EFTable":"","DoubleLaneGap":p["WardLaneGap"]])
        let ef=try ScrollCompensation(sec.loop(first,false),&efParameters,1)
        let firstPath=measured ? try offsetAtSection(sec,sec.loop(first,false),false,Array(repeating:offsets[0],count:sec.nodes.count)):ef.at(Array(repeating:0,count:sec.nodes.count))
        guard [0.0,1.0].contains(p["WardLayerMode"]) else {throw SliceFailure("层高策略无效。")}
        guard nominal<=3.5,first<=3.5 else {throw SliceFailure("挂衣体目前支持层高和首层层高不大于 3.5 mm；圆角搭接按实际路径校核。")}
        let metadata=["; WARDROBE_VASE=1","; WARDROBE_PART=\(sec.part)","; WARDROBE_PART_COUNT=\(sec.partCount)","; WARDROBE_PRINTED_OPENING=1","; WARDROBE_BED_TEST=\(bedTest ? 1:0)","; WARDROBE_TEST_CONTINUOUS=\(continuousTest ? 1:0)","; WARDROBE_START_RISE="+(!bedTest || continuousTest ? "BOUNDED_LOCAL_LEAD":"PLANAR"),"; WARDROBE_TOP_TRANSITION="+(bedTest ? "NONE":"BOUNDED_REVERSE_LEAD")]
        var headerParameters=p;headerParameters["CH"]=height
        var lines=helicalHeader(headerParameters,kind:"WARDROBE",pitch:nominal,start:firstPath[0],metadata:metadata)
        lines.removeAll{$0.hasPrefix("; EF_")}
        let efMetadata=["; EF_AMOUNT="+fmt(amount),"; WARDROBE_EF_GEOMETRIC=1","; WARDROBE_EF_FIRST_LAYER_ONLY=\(measured ? 0:1)","; WARDROBE_EF_TRANSITION_TURNS=\(measured ? offsets.count:(amount != 0 && (!bedTest || continuousTest) ? 1:0))","; WARDROBE_EF_LAYER_OFFSETS_MM="+(measured ? offsets.map{fmt($0)}.joined(separator:",")+",0":"LEGACY"),"; WARDROBE_EF_INTERPOLATION="+(measured ? "SMOOTH_BETWEEN_LAYER_ANCHORS":"FIRST_TURN")]
        lines.insert(contentsOf:efMetadata,at:lines.firstIndex(of:"; E_UNITS=VOLUME_MM3")!)
        var wall=[SlicePoint](),previous:[SlicePoint]?,turn=0,maxSupport=0.0,gapRange=[Double.infinity,0],pitchRange=[Double.infinity,0],rimCount=0
        func emit(_ points:[SlicePoint],_ hs:[Double],finish:Bool=false) throws {
            if let previous=previous {let d=previous.last!-points[0];guard sqrt(d.x*d.x+d.y*d.y+d.z*d.z)<=1e-6 else {throw SliceFailure("挂衣体连续路径接点不一致。")}}
            lines.append("; GH_WALL_TURN=\(turn)");turn+=1;if finish {lines.append("; GH_RIM_FINISH_START")}
            for i in 1..<points.count {
                let q=points[i],h=(hs[i-1]+hs[i])/2
                guard h.isFinite,h>0,h<=width else {throw SliceFailure(String(format:"挂衣体实际层间隙无效：%.4f mm。",h))}
                let e=xyLength(points[i-1],q)*h*(width-edge*h)
                guard e>0 else {throw SliceFailure("挂衣体出现退化挤出段。")};gapRange[0]=min(gapRange[0],h);gapRange[1]=max(gapRange[1],h)
                lines += ["; GH_GAP_HEIGHT="+fmt(h),"G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(fmt(q.z)) E\(fmt(e)) F420"]
            }
            if finish {lines.append("; GH_RIM_FINISH_END")};wall += previous==nil ? points:Array(points.dropFirst());previous=points
        }
        func stage(_ bottom:Double,_ top:Double,_ opened:Bool,finishRim:Bool=true) throws {
            let baseLoop=sec.loop(bottom,opened),fractions=pathFractions(baseLoop),length=(1..<baseLoop.count).reduce(0){$0+xyLength(baseLoop[$1-1],baseLoop[$1])}
            let spans=opened && p["WardLayerMode"]==0 ? [(bottom,min(top,sec.B+sec.R),nominal*0.60),(min(top,sec.B+sec.R),top,nominal)]:[(bottom,top,opened ? nominal*0.988:nominal)]
            var schedule=[(Double,Double)]()
            for (lo,hi,maximum) in spans {if hi<=lo {continue};let count=Int(ceil((hi-lo)/maximum-1e-9)),pitch=(hi-lo)/Double(count);schedule += (0..<count).map{(lo+Double($0)*pitch,pitch)}}
            let n=schedule.count;var fixedXY:[SlicePoint]?
            for (lap,pair) in schedule.enumerated() {
                let (base,pitch)=pair;pitchRange[0]=min(pitchRange[0],pitch);pitchRange[1]=max(pitchRange[1],pitch)
                var zs=fractions.map{base+(lap==0 ? firstRise($0,pitch,length):pitch*$0)}
                if finishRim && lap==n-1 {zs=zip(zs,fractions).map{$0-(firstRise(1-$1,pitch,length)-pitch*(1-$1))}}
                var points:[SlicePoint]
                if sec.endpoint(base,opened)==sec.endpoint(base+pitch,opened) {
                    if fixedXY==nil {fixedXY=sec.loop(base,opened)};points=zip(fixedXY!,zs).map{SlicePoint($0.x,$0.y,$1)}
                }else{points=zip(sec.nodes,zs).map{sec.at($0,$1,opened)}}
                if lap==n-1 {points[points.count-1].z=top}
                if measured && fractions.contains(where:{measuredLayerOffset(offsets,Double(lap)+$0)>0}) {
                    points=try offsetAtSection(sec,points,opened,fractions.map{measuredLayerOffset(offsets,Double(lap)+$0)});try ef.check(points)
                }else if !measured && amount != 0 && lap==0 {
                    points=points.indices.map{i in let q=points[i],normal=ef.normals[i],f=ef.profile(fractions[i]);return SlicePoint(q.x+amount*f*normal.x,q.y+amount*f*normal.y,q.z)};try ef.check(points)
                }
                var hs:[Double]
                if opened || lap<=1 || (measured && lap<=offsets.count) || (finishRim && lap==n-1) {
                    let result=try underlayHeights(previous!,points,sec.half+0.25);hs=result.0;maxSupport=max(maxSupport,result.1)
                    hs[0]=max(0,points[0].z-previous![0].z);hs[hs.count-1]=max(0,points.last!.z-previous!.last!.z)
                }else{hs=Array(repeating:pitch,count:fractions.count)}
                try emit(points,hs)
            }
            if !finishRim {return}
            let points=sec.loop(top,opened),result=try underlayHeights(previous!,points,sec.half+0.25);var hs=result.0;maxSupport=max(maxSupport,result.1)
            hs[0]=max(0,points[0].z-previous![0].z);hs[hs.count-1]=max(0,points.last!.z-previous!.last!.z)
            try emit(points,hs,finish:true);rimCount+=1
        }
        try emit(firstPath,Array(repeating:first,count:sec.nodes.count))
        if continuousTest {try stage(first,height,false,finishRim:false)}else if bedTest {
            for layer in 1..<Int(testLayers) {
                let z=first+nominal*Double(layer);lines.append("G0 Z"+fmt(z)+" F600");var planar=sec.loop(z,false)
                if measured {planar=try offsetAtSection(sec,planar,false,Array(repeating:layer<offsets.count ? offsets[layer]:0,count:sec.nodes.count))}
                if amount != 0 && (layer==1 || measured) {lines.append("G0 X\(fmt(planar[0].x)) Y\(fmt(planar[0].y)) F3000")}
                previous=nil;try emit(planar,Array(repeating:nominal,count:sec.nodes.count))
            }
            pitchRange=[nominal,nominal]
        }else if sec.constantSection {try stage(first,height,false)}else{lines.append("; WARDROBE_NOTCH_OPEN_FROM_FIRST_LAYER");try stage(first,height,true)}
        lines += [bedTest ? "; WARDROBE_TEST_LAYERS=\(Int(testLayers))":"; WARDROBE_RIM_DONE=1","; ===== PRINT PATH END ====="]
        let info=wardrobeDescription(p,sec,height:height,bedTest:bedTest,continuousTest:continuousTest,testLayers:Int(testLayers),testPitch:testPitch,pitchRange:pitchRange,amount:amount,measured:measured,offsets:offsets)
        var meta:[String:Any]=["ef_measured":measured,"ef_layer_offsets_mm":offsets,"ef_amount":amount,"bed_test":bedTest,"coil_outer_radius":sec.coilOuterRadius,"turn_pitch_range":pitchRange,"layer_mode":p["WardLayerMode"],"core_mode":p["WardCoreMode"],"curl_reduction":p["WardCurlReduction"],"part":sec.part,"bounds":sec.bounds,"skirt_envelope":sec.maxEnvelope,"bore":sec.measuredBore,"required_bore":sec.bore,"effective_width":sec.effective,"needed_width":sec.need,"rotation":sec.rotation*180/Double.pi,"pipe_print":[sec.pipePrint.x,sec.pipePrint.y],"center_installation":[sec.center.x,sec.center.y],"opening_width":sec.hole,"opening_height":sec.openingHeight,"part_count":sec.partCount,"max_underlay_distance":maxSupport,"gap_range":gapRange,"level_rims":rimCount,"segments":wall.count-1]
        if sec.partCount==9 {meta.merge(sec.dims.mapValues{$0 as Any}){_,new in new};meta["assembly_start"]=sec.assemblyStart}
        if try wardrobeLayout(p)==2 {meta.merge(sec.dims.mapValues{$0 as Any}){_,new in new};meta.merge(["assembly_start":sec.assemblyStart,"assembly_end":sec.assemblyEnd,"layout":2,"rail_included":false]){_,new in new}}
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:wall,wall:wall,sectionCount:1,details:["wardrobe":meta])
    }
}
