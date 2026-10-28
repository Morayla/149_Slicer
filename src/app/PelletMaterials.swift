import Foundation

struct PelletMaterial:Decodable,Identifiable {
    let id:String
    let name:String
    let fields:[String:Double] // Native UI units: speeds in mm/s.
    let trialFlow:Double?
    let maxTrialSpeed:Double?
}

/// Presets only change material/thermal/print-feed fields. Geometry, extrusion
/// calibration, Z offsets, compensation and retractions are deliberately absent.
final class PelletMaterialStore {
    static let keys=["Density","NT","BT","ZONE1","ZONE2","ZONE3","F","BottomF","WallF","SKIRT_F","MeshSpeed"]
    let materials:[PelletMaterial]
    private let defaults:UserDefaults
    private let storageKey="149.pelletMaterialRecipes.v1"
    init(url:URL,defaults:UserDefaults = .standard) throws {
        materials=try JSONDecoder().decode([PelletMaterial].self,from:Data(contentsOf:url))
        self.defaults=defaults
    }
    private var saved:[String:[String:String]] {
        defaults.dictionary(forKey:storageKey) as? [String:[String:String]] ?? [:]
    }
    func save(id:String,fields:[String:String]) throws {
        guard materials.contains(where:{$0.id==id}) else {throw error("未知的颗粒材料。")}
        var recipe:[String:String]=[:]
        for key in Self.keys {
            guard let text=fields[key],let n=Double(text),n.isFinite,n>=0,
                  key != "Density" || (n>=0.01 && n<=30),
                  !["F","BottomF","WallF","SKIRT_F","MeshSpeed"].contains(key) || n>0 else {
                throw error("\(key) 的材料参数无效，未保存。")
            }
            recipe[key]=text
        }
        var all=saved;all[id]=recipe;defaults.set(all,forKey:storageKey)
    }
    func select(_ id:String,from current:[String:String],reset:Bool=false)throws->[String:String] {
        guard let material=materials.first(where:{$0.id==id}) else {throw error("未知的颗粒材料。")}
        // Compute first: an invalid draft must not partially overwrite a recipe.
        var next=current
        if !reset,let recipe=saved[id] {
            for key in Self.keys {if let text=recipe[key] {next[key]=text}}
        } else {
            for (key,value) in material.fields {next[key]=String(format:"%.9g",value)}
            if let flow=material.trialFlow,let cap=material.maxTrialSpeed {
                for (key,value) in try Self.trialSpeeds(current,flow:flow,cap:cap) {next[key]=value}
            }
        }
        next["PelletMaterial"]=id
        return next
    }
    static func trialSpeeds(_ fields:[String:String],flow:Double,cap:Double)throws->[String:String] {
        func n(_ key:String)throws->Double {
            guard let x=Double(fields[key] ?? ""),x.isFinite,x>0 else {throw error("\(key) 需要为正数，才能计算材料试验速度。")}
            return x
        }
        let w=try n("W"),wb=try n("WB"),h=try n("H"),h0=try n("H0"),bh=try n("BH")
        let pitch=fields["SourceMode"]=="Triple" ? try n("TriplePitch"):h
        let factor=try n("PF") * n("FM") * max(1,n("F0"))
        // A rectangular section intentionally overestimates the usual rounded
        // bead area; this is a trial feed estimate, never a measured flow limit.
        func speed(_ area:Double)->String {String(format:"%.6f",min(cap,flow/(area*factor)))}
        return ["F":speed(w*max(pitch,h0)),"WallF":speed(w*max(pitch,h0)),
                "BottomF":speed(wb*max(bh,h0)),"SKIRT_F":speed(max(w,wb)*h0),
                "MeshSpeed":speed(w * (try n("MeshStrand")))]
    }
    static func error(_ text:String)->NSError {NSError(domain:"PelletMaterial",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    private func error(_ text:String)->NSError {Self.error(text)}
}
