import SwiftUI

struct MaterialRecipeSelector: View {
    @ObservedObject var model: Workbench
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                uiText("材料").font(.headline)
                if model.materialModified { uiText("已修改").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    editing = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless).help(L("编辑材料")).accessibilityLabel(L("编辑材料"))
            }
            ParameterPicker(
                L("预设"),
                selection: Binding(
                    get: { model.selectedRecipe?.id ?? "" },
                    set: { id in
                        if let recipe = model.materialRecipes.first(where: { $0.id == id }) {
                            model.selectMaterialRecipe(recipe)
                        }
                    }), options: model.materialRecipes.map { .init($0.name, $0.id, localize: false) }
            ).labelsHidden()
        }.sheet(isPresented: $editing) { MaterialEditor(model: model) }
    }
}

struct MaterialEditor: View {
    @ObservedObject var model: Workbench
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MaterialRecipe
    @State private var error: String?
    init(model: Workbench) {
        self.model = model
        var recipe =
            model.selectedRecipe
            ?? MaterialRecipe(
                id: UUID().uuidString, name: L("自定义材料"),
                profile: model.materialProfile, material: model.materialIdentity, fields: [:],
                appearance: model.materialAppearance)
        recipe.fields = model.fields.filter { model.materialFieldKeys.contains($0.key) }
        recipe.appearance = model.materialAppearance
        _draft = State(initialValue: recipe)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                uiText("编辑材料").font(.headline)
                Spacer()
                Text(model.isBambu ? model.materialProfile + " mm" : "Ginger G1").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        uiText("名称")
                        TextField(L("名称"), text: $draft.name).textFieldStyle(.roundedBorder)
                    }
                    number("密度", "Density", "g/cm³")
                    section("温度")
                    number("喷嘴", "NT", "°C")
                    number("热床", "BT", "°C")
                    if !model.isBambu {
                        ForEach(1...3, id: \.self) { zone in number("热区 \(zone)", "ZONE\(zone)", "°C") }
                    }
                    section("挤出校正")
                    number("流量比例", "FM", "×")
                    if model.isBambu {
                        number("最大体积流量", "MaxVolumetric", "mm³/s")
                        number("冷却风扇", "BBFan", "%")
                    } else {
                        number("颗粒挤出系数", "PF", "×")
                    }
                    section("回抽与恢复")
                    if model.isBambu {
                        number("回抽长度", "BBRetraction", "mm")
                        number("回抽速度", "BBRetractionSpeed", "mm/s")
                    } else {
                        number("回抽体积", "G1_RETRACT", "mm³")
                        number("回抽速度", "G1_RETRACT_F", "mm³/s")
                        number("恢复速度", "G1_RESTORE_F", "mm³/s")
                        number("额外恢复体积", "G1_RESTART_EXTRA", "mm³")
                    }
                    section("外观")
                    ColorPicker(
                        L("颜色"),
                        selection: Binding(
                            get: { Color(nsColor: draft.appearance.color) },
                            set: { color in
                                if let rgb = NSColor(color).usingColorSpace(.sRGB) {
                                    draft.appearance.red = rgb.redComponent
                                    draft.appearance.green = rgb.greenComponent
                                    draft.appearance.blue = rgb.blueComponent
                                }
                            }), supportsOpacity: false)
                    optical("透光率", $draft.appearance.transmission, 0...1)
                    optical("粗糙度", $draft.appearance.roughness, 0...1)
                    optical("折射率", $draft.appearance.ior, 1...2.5)
                    MaterialSample(appearance: draft.appearance).frame(height: 150).clipShape(
                        RoundedRectangle(cornerRadius: 8))
                }.padding(.trailing, 6)
            }
            if let error { uiText(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L("另存为新材料")) { save(copy: true) }
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存")) { save(copy: false) }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 480, height: 650)
    }
    private func section(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.top, 4)
            uiText(title).font(.headline)
        }
    }
    private func number(_ title: String, _ key: String, _ unit: String) -> some View {
        HStack(spacing: 8) {
            uiText(title)
            Spacer()
            NumericField(L(title), text: Binding(get: { draft.fields[key] ?? "" }, set: { draft.fields[key] = $0 }))
                .frame(width: ParameterLayout.valueWidth, height: 26)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
        }
    }
    private func optical(_ title: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            uiText(title).frame(width: 72, alignment: .leading)
            Slider(value: binding, in: range)
            NumericField(L(title), value: binding, step: 0.01).frame(width: 72, height: 26)
        }
    }
    private func save(copy: Bool) {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "请输入材料名称。"
            return
        }
        for (key, text) in draft.fields {
            guard let value = Double(text), value.isFinite, value >= 0,
                !["Density", "FM", "PF", "MaxVolumetric", "G1_RETRACT_F", "G1_RESTORE_F", "BBRetractionSpeed"].contains(
                    key) || value > 0,
                key != "BBFan" || value <= 100
            else {
                error = "请检查数值和单位。"
                return
            }
        }
        guard draft.appearance.valid else {
            error = "请检查外观参数的范围。"
            return
        }
        var recipe = draft
        if copy { recipe.id = UUID().uuidString }
        do {
            try model.saveMaterialRecipe(recipe)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
