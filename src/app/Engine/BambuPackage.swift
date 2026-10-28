import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

extension NativeBambu {
    static func thumbnail(_ rows:[[Double]],to url:URL,size:Int=384) throws {
        let rows=rows.filter{$0[6] != 4};guard !rows.isEmpty else {throw SliceFailure("没有可预览的打印路径。")}
        func project(_ x:Double,_ y:Double,_ z:Double)->SIMD2<Double> {SIMD2(0.866*(x-y),0.5*(x+y)-z)}
        let points=rows.map{project($0[3],$0[4],$0[5])},x0=points.map(\.x).min()!,y0=points.map(\.y).min()!,x1=points.map(\.x).max()!,y1=points.map(\.y).max()!,scale=Double(size-48)/max(x1-x0,y1-y0,1),center=SIMD2((x0+x1)/2,(y0+y1)/2)
        var pixels=[UInt8]();pixels.reserveCapacity(size*size*4);for _ in 0..<size*size {pixels += [32,33,35,255]}
        for index in stride(from:0,to:rows.count,by:max(1,rows.count/60000)) {
            let row=rows[index],a=(project(row[0],row[1],row[2])-center)*scale+SIMD2(repeating:Double(size)/2),b=(project(row[3],row[4],row[5])-center)*scale+SIMD2(repeating:Double(size)/2),n=max(1,Int(max(abs(b.x-a.x),abs(b.y-a.y))))
            for i in 0...n {let q=a+(b-a)*Double(i)/Double(n),x=Int(q.x.rounded(.toNearestOrEven)),y=Int(q.y.rounded(.toNearestOrEven));if x>=0 && x<size && y>=0 && y<size {let k=(y*size+x)*4;pixels[k]=211;pixels[k+1]=213;pixels[k+2]=215}}
        }
        guard let provider=CGDataProvider(data:Data(pixels) as CFData),let image=CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else {throw SliceFailure("无法创建路径缩略图。")}
        CGImageDestinationAddImage(destination,image,nil);guard CGImageDestinationFinalize(destination) else {throw SliceFailure("无法保存路径缩略图。")}
    }
    static func package(project:NativeSliceProject,plan:Plan,stats:[String:Any],gcode:String,segments:[[Double]],to destination:URL) throws {
        let m=project.machine,s=SliceParameters(stats),nozzle=G.fmt(m["Nozzle"]),gcodeData=Data(gcode.utf8),hash=Insecure.MD5.hash(data:gcodeData).map{String(format:"%02x",$0)}.joined()
        var config=plan.config
        let ids=config["filament_ids"] as? [String] ?? ["GFG99"],nozzleMap=(config["filament_nozzle_map"] as? [String])?.first ?? "0",filamentMap=(config["filament_map"] as? [String])?.first ?? "1"
        guard !ids.isEmpty else {throw SliceFailure("官方配置缺少材料编号。")}
        let diameters=m.text("PrinterModel")=="H2D" ? (config["nozzle_diameter"] as? [String] ?? []):[nozzle]
        guard !diameters.isEmpty else {throw SliceFailure("官方配置缺少喷嘴直径。")}
        config.merge(["print_compatible_printers":[(config["printer_model"] as? String ?? plan.profile.name)+" "+nozzle+" nozzle"],"curr_bed_type":m.text("BuildPlate"),"enable_arc_fitting":"0","filament_ids":ids,"filament_type":[m.text("FilamentType")],"filament_diameter":["1.75"],"filament_colour":["#D3D5D7"]] as [String:Any]){_,new in new}
        func escape(_ value:String)->String {value.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"'",with:"&apos;")}
        func metadata(_ values:[String:String])->String {values.keys.sorted().map{"<metadata key=\"\(escape($0))\" value=\"\(escape(values[$0]!))\"/>"}.joined()}
        func attributes(_ values:[String:String])->String {values.keys.sorted().map{"\($0)=\"\(escape(values[$0]!))\""}.joined(separator:" ")}
        let xml="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",name="149 "+m.text("PrinterModel")
        let sliceMeta:[String:String]=["index":"1","printer_model_id":plan.modelID,"nozzle_diameters":diameters.joined(separator:","),"nozzle_volume_type":diameters.map{_ in "0"}.joined(separator:" "),"filament_maps":filamentMap,"filament_map_mode":"Manual","enable_filament_dynamic_map":"false","prediction":String(Int((s["motion_minutes"]*60).rounded(.toNearestOrEven))),"weight":G.fmt(s["mass_g"]),"support_used":"0","label_object_enabled":"0","gcode_file":"Metadata/plate_1.gcode","gcode_md5":hash,"timelapse_type":"0","plate_name":name]
        let filament:[String:String]=["id":"1","tray_info_idx":ids[0],"type":m.text("FilamentType"),"color":"#D3D5D7","used_m":String(s["volume_mm3"]/(Double.pi*1.75*1.75/4)/1000),"used_g":G.fmt(s["mass_g"]),"group_id":nozzleMap,"nozzle_diameter":nozzle,"volume_type":"Standard","used_for_object":"true","used_for_support":"false"]
        let slices=xml+"<config><plate>"+metadata(sliceMeta)+"<filament "+attributes(filament)+"/></plate></config>"
        let models=xml+"<config><plate>"+metadata(["plater_id":"1","locked":"false","filament_maps":filamentMap,"filament_map_mode":"Manual","gcode_file":"Metadata/plate_1.gcode","thumbnail_file":"Metadata/plate_1.png","top_file":"Metadata/plate_1.png","pick_file":"Metadata/plate_1.png","plate_name":name])+"</plate></config>"
        let modelXML=#"<?xml version="1.0" encoding="UTF-8"?><model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><metadata name="Application">149 slicer</metadata><metadata name="Description">Pre-sliced custom toolpaths. No re-sliceable model included.</metadata><resources/><build/></model>"#
        let content=#"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="gcode" ContentType="text/plain"/><Default Extension="config" ContentType="application/octet-stream"/></Types>"#
        let rels=#"<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>"#
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("149-package-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        for path in ["_rels","3D","Metadata"] {try FileManager.default.createDirectory(at:folder.appendingPathComponent(path),withIntermediateDirectories:true)}
        for (path,text) in ["[Content_Types].xml":content,"_rels/.rels":rels,"3D/3dmodel.model":modelXML,"Metadata/plate_1.gcode":gcode,"Metadata/plate_1.gcode.md5":hash,"Metadata/slice_info.config":slices,"Metadata/model_settings.config":models] {try text.write(to:folder.appendingPathComponent(path),atomically:true,encoding:.utf8)}
        try JSONSerialization.data(withJSONObject:config,options:[.sortedKeys]).write(to:folder.appendingPathComponent("Metadata/project_settings.config"))
        try thumbnail(segments,to:folder.appendingPathComponent("Metadata/plate_1.png"))
        _=try NativeSliceProcess.run(URL(fileURLWithPath:"/usr/bin/ditto"),["-c","-k","--norsrc",folder.path,destination.path],timeout:60)
    }
}
