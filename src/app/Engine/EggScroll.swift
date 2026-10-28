import Foundation

extension SliceGeometry {
    static func eggModel(_ p:SliceParameters,resources:URL) throws -> SliceShape {
        let height=p["EggHeight"],width=p["W"],first=p["H0"],nominal=p["H"],depth=p["CH"]
        guard height>=50,height<=950 else {throw SliceFailure("整体高度需为 50–950 mm。")}
        let profile=try readProfile(resources,"egg_scroll_profile"),raw=profile["path"] as! [[Double]],low=raw.map{$0[1]}.min()!,high=raw.map{$0[1]}.max()!,guardGap=0.83
        let minScale=max((width+guardGap)/3,(width/2+0.4)/(profile["tip_radius"] as! Double)),minHeight=ceil(width+(high-low)*minScale)
        guard height>=minHeight else {throw SliceFailure(String(format:"当前 %.1f mm 线宽下，整体高度至少 %.0f mm，才能保留卷尖回转及双线净空；请增大高度或减小线宽。",width,minHeight))}
        let scale=(height-width)/(high-low),poly=raw.map{SlicePoint($0[0]*scale,($0[1]-(high+low)/2)*scale,0)}
        var dense=[SlicePoint]()
        for i in poly.indices {
            let a=poly[i],b=poly[(i+1)%poly.count],n=max(1,Int(ceil(xyLength(a,b)/1.5)))
            for j in 0..<n {let q=a+(b-a)*Double(j)/Double(n);dense.append(SlicePoint(Double(fmt(q.x,places:5))!,Double(fmt(q.y,places:5))!,0))}
        }
        let minimum:Double
        do {minimum=min(try checkSpacing(dense,width:width+guardGap),3*scale)}catch {throw SliceFailure("蛋形双卷的料道校核未通过，请增大整体高度。"+error.localizedDescription)}
        let frontWidth=poly.map{$0.x}.max()!-poly.map{$0.x}.min()!+width,path=alignedLoop(poly,p.flag("AlignLeft"))
        guard depth>=first+nominal else {throw SliceFailure("自动进深不足以容纳首层与一个完整层高。")}
        let fractions=pathFractions(path),turns=max(1,Int(ceil((depth-first)/nominal-1e-9))),pitch=(depth-first)/Double(turns)
        guard (path.count-1)*(turns+2)<=220_000 else {throw SliceFailure("墙角螺旋路径超过 22 万段，请降低模块高度或增大层高。")}
        var lines=helicalHeader(p,kind:"EGG_SCROLL",pitch:pitch,start:path[0],metadata:["; EGG_SCROLL_VASE=1","; EGG_SCROLL_FRONT_HEIGHT="+fmt(height)])
        let result=try helicalPath(p,fractions:fractions,marker:"EGG_SCROLL",lines:&lines,at:{i,z in SlicePoint(path[i].x,path[i].y,z)})
        let info=String(format:"蛋形海螺双卷 | 只调整整体高度，其他造型尺寸自动同比例变化。\n使用姿态：高 %.1f × 宽 %.1f × 深 %.1f mm。打印时正面朝上平放，Z 为进深。\n线宽 %.1f mm；双线最小净空约 %.2f mm；卷尖回转内侧半径 %.2f mm。\n当前线宽下最小整体高度 %.0f mm；改变高度或线宽后重新检查。\n单条闭合路径，首层等高，随后连续升 Z；%d 周，实际层高 %.4f mm。\n沿用蛋形曲线与渐展双卷；已做中心线自交和标称料宽校核，承托能力与实物成形需试样验证。",height,frontWidth,height*80/650,width,minimum-width,1.5*scale-width/2,minHeight,turns,pitch)
        let details:[String:Any]=["front_height":height,"width":frontWidth,"depth":height*80/650,"minimum_height":minHeight,"minimum_spacing":minimum,"clear_gap":minimum-width,"tip_center_spacing":3*scale,"tip_inner_radius":1.5*scale-width/2,"scale":scale,"path":path,"actual_pitch":pitch,"rise_turns":turns]
        return SliceShape(gcode:lines.joined(separator:"\n"),info:info,parameters:p,points:result.wall,wall:result.wall,sectionCount:1,details:["egg":details])
    }
}
