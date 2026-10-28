import SwiftUI

struct PelletMaterialControls:View {
    @ObservedObject var model:Workbench
    @ObservedObject private var language=AppLanguage.shared
    @State private var store:PelletMaterialStore?
    @State private var notice=""
    private var selected:String {model.fields["PelletMaterial"] ?? "polymaker_petg1000"}
    private var cafblo:Bool {selected=="cafblo_rsd038_4r0001"}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if let store=store {
                PresetHeader("颗粒材料") {
                    Button(L("保存材料参数")) {
                        do {try store.save(id:selected,fields:model.fields);notice=L("已保存此材料的密度、温度与打印速度。")}
                        catch {model.error=L(error.localizedDescription)}
                    }
                    Button(L("恢复材料起点")) {
                        do {model.fields=try store.select(selected,from:model.fields,reset:true);model.dirty=true;notice=L("已恢复材料试验起点；可调整后保存。")}
                        catch {model.error=L(error.localizedDescription)}
                    }.disabled(selected=="custom")
                }
                Picker(L("颗粒材料"),selection:Binding(get:{selected},set:{id in
                    do {
                        model.fields=try store.select(id,from:model.fields);model.dirty=true
                        notice=L("已载入材料参数，请重新切片。")
                    } catch {model.error=L(error.localizedDescription)}
                })) {
                    ForEach(store.materials) {uiText($0.name).tag($0.id)}
                }.labelsHidden().accessibilityLabel(L("颗粒材料"))

            }
            if !notice.isEmpty {Text(verbatim:notice).interfaceFont(.caption).foregroundColor(.secondary)}
            NumberRow(model:model,label:"材料密度",key:"Density",unit:"g/cm³")
            NumberRow(model:model,label:"额外耗料",key:"ExtraWasteG",unit:"g")
            ContextHelp("选择材料即载入预设；修改只影响当前项目，点击保存才更新材料预设。密度仅影响用料克数。")
            if cafblo {
                uiText("透明微蓝 · RSD038-4R0001").interfaceFont(.subheadline)
                ContextHelp("热区 1 / 2 / 3：210 / 220 / 230°C，来自 Ginger G1-Base 实例。独立喷嘴 230°C 与热床 90°C 为可调整的试验起点。")
                if ["NT","ZONE1","ZONE2","ZONE3"].contains(where:{(Double(model.fields[$0] ?? "") ?? 0)>240}) {
                    uiText("当前温度超过 240°C；厂家提示可能起泡或降解。").interfaceFont(.caption).foregroundColor(.orange)
                }
                DisclosureGroup(L("材料依据与试验速度")) {
                    VStack(alignment:.leading,spacing:8) {
                        uiText("密度 1.28 g/cm³，引用 RSD038 type R 的实体密度；透明微蓝牌号对应打印实例，不是自然色版本。")
                        uiText("厂家速度 48–150 mm/s 对应 1 mm 喷嘴、1.2 mm 层高、2 mm 线宽。当前试验起点按 50 mm³/s 的试验预算与料道截面积计算，并限制在 10 mm/s 内；这是软件试验估算，不是厂家最大流量。")
                        uiText("恢复材料起点会按当前线宽、层高和流量倍率重算速度。修改尺寸后请重新评估；波形、接触与冷却效果仍需实打验证。")
                        uiText("干燥：80°C，3–5 小时；避免过夜或长期烘干。厂家不建议使用除湿循环再生式料斗干燥机。热床参考范围 80–100°C。")
                        uiText("回收性能文件没有提供另一套密度或温度，故不另设回收料配方。MFR 7 g/10 min 是材料测试值，不能当作打印体积流量上限。")
                        uiText("依据：CAFBLO 3D Printing Technology ver5，第 3、6、7 页；RSD038 type R Physical Properties，第 1 页；Recycled properties ver3。")
                    }.interfaceFont(.caption).foregroundColor(.secondary).padding(.top,6)
                }
            }
        }.onAppear {
            do {store=try PelletMaterialStore(url:Bundle.main.resourceURL!.appendingPathComponent("g1mini/pellet_materials.json"))}
            catch {model.error=error.localizedDescription}
        }
    }
}
