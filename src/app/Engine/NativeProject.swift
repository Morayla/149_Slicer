import Foundation
import CoreFoundation

struct NativeSliceProject {
    var shape:SliceParameters,machine:SliceParameters,process:SliceParameters,material:SliceParameters
    var dictionary:[String:Any] {["version":1,"shape":shape.values,"machine":machine.values,"process":process.values,"material":material.values]}
    init(_ raw:[String:Any],defaults:[String:Any]) throws {
        guard (raw["version"] as? NSNumber)?.doubleValue==1 else {throw SliceFailure("不支持的项目版本。")}
        func group(_ name:String) throws -> SliceParameters {
            let initial=defaults[name] as! [String:Any]
            guard raw[name]==nil || raw[name] is [String:Any] else {throw SliceFailure(name+" 必须为参数对象。")}
            let values=raw[name] as? [String:Any] ?? [:],unknown=Set(values.keys).subtracting(initial.keys)
            guard unknown.isEmpty else {throw SliceFailure("本版不支持参数："+unknown.sorted().joined(separator:", "))}
            var result=initial.merging(values){_,new in new}
            for (key,standard) in initial {
                if standard is NSNumber {
                    let value=(result[key] as? NSNumber)?.doubleValue ?? Double(result[key] as? String ?? "") ?? .nan
                    guard value.isFinite,abs(value)<1e12 else {throw SliceFailure(key+" 必须是有效的有限数值。")}
                    if CFGetTypeID(standard as CFTypeRef)==CFBooleanGetTypeID() {guard value==0 || value==1 else {throw SliceFailure(key+" 必须为开启或关闭。")};result[key]=value != 0}else{result[key]=value}
                }else if standard is String {guard result[key] is String else {throw SliceFailure(key+" 必须为文本。")}}
            }
            return SliceParameters(result)
        }
        shape=try group("shape");machine=try group("machine");process=try group("process");material=try group("material")
        // Bound sampling arithmetic before any floating-point count becomes an
        // integer allocation. These bounds include every supported print mode.
        for key in ["W","WB","H","H0","BH","TriplePitch"] {
            guard (0.001...1000).contains(shape[key]) else {throw SliceFailure(key+" 必须在 0.001–1000 mm 之间。")}
        }
        for key in ["CH","Dout","EllipseMajor","EllipseMinor"] {
            guard shape[key]>0,shape[key]<=10000 else {throw SliceFailure(key+" 必须大于 0 且不超过 10000 mm。")}
        }
    }
}
