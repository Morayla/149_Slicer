import Foundation

struct MaterialRecipe: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var profile: String
    var material: String
    var fields: [String: String]
    var appearance: MaterialAppearance

    static let pelletKeys: Set<String> = [
        "Density", "NT", "BT", "ZONE1", "ZONE2", "ZONE3", "FM", "PF",
        "G1_RETRACT", "G1_RESTART_EXTRA", "G1_RETRACT_F", "G1_RESTORE_F",
    ]
    static let filamentKeys: Set<String> = [
        "Density", "NT", "BT", "FM", "MaxVolumetric", "BBFan",
        "BBRetraction", "BBRetractionSpeed",
    ]
    static let storageKey = "149.material.recipes.v2"
}

extension Workbench {
    var materialProfile: String { isBambu ? printerModel + ":" + (fields["Nozzle"] ?? "0.4") : printerModel }
    var materialFieldKeys: Set<String> { isBambu ? MaterialRecipe.filamentKeys : MaterialRecipe.pelletKeys }
    var materialRecipes: [MaterialRecipe] {
        let saved = savedMaterialRecipes.filter { $0.profile == materialProfile }
        let base = factoryMaterialRecipes.map { original in saved.first { $0.id == original.id } ?? original }
        return base + saved.filter { custom in !base.contains { $0.id == custom.id } }
    }
    var selectedRecipe: MaterialRecipe? {
        materialRecipes.first { $0.id == selectedMaterialRecipeID }
            ?? materialRecipes.first { $0.material == materialIdentity }
    }
    var materialModified: Bool {
        guard let recipe = selectedRecipe else { return false }
        return recipe.appearance != materialAppearance
            || recipe.fields.contains { Double(fields[$0.key] ?? "") != Double($0.value) }
    }
    func prepareMaterialLibrary() {
        savedMaterialRecipes =
            preferences.data(forKey: MaterialRecipe.storageKey)
            .flatMap { try? JSONDecoder().decode([MaterialRecipe].self, from: $0) } ?? []
        var baseline = fields.filter { materialFieldKeys.contains($0.key) }
        if !isBambu, let machine = defaults["machine"] as? [String: Any] {
            for key in MaterialRecipe.pelletKeys {
                if let value = machine[key] as? NSNumber {
                    baseline[key] = NumericField.format(
                        speedKeys.contains(key) ? value.doubleValue / 60 : value.doubleValue)
                }
            }
        }
        let choices: [(String, String, [String: Double])]
        if isBambu {
            choices = ["PLA", "PETG", "TPU"].map { ("filament:" + $0, $0, [:]) }
        } else {
            choices = materialCatalog.map { ("pellet:" + $0.id, $0.name, $0.fields) }
        }
        let oldRecipes =
            preferences.dictionary(forKey: "149.pelletMaterialRecipes.v1") as? [String: [String: String]] ?? [:]
        factoryMaterialRecipes = choices.map { identity, name, values in
            var recipeFields = baseline
            for (key, value) in values where materialFieldKeys.contains(key) {
                recipeFields[key] = NumericField.format(value)
            }
            for (key, value) in oldRecipes[String(identity.dropFirst(7))] ?? [:] where materialFieldKeys.contains(key) {
                recipeFields[key] = value
            }
            return MaterialRecipe(
                id: materialProfile + ":" + identity, name: name, profile: materialProfile,
                material: identity, fields: recipeFields, appearance: .initial(for: identity))
        }
        selectedMaterialRecipeID =
            preferences.string(forKey: "149.material.selected." + materialProfile)
            ?? materialProfile + ":" + materialIdentity
        if selectedRecipe?.material != materialIdentity {
            selectedMaterialRecipeID = materialProfile + ":" + materialIdentity
        }
    }
    func selectMaterialRecipe(_ recipe: MaterialRecipe) {
        selectedMaterialRecipeID = recipe.id
        preferences.set(recipe.id, forKey: "149.material.selected." + materialProfile)
        var next = fields
        next.merge(recipe.fields, uniquingKeysWith: { _, new in new })
        if recipe.material.hasPrefix("pellet:") {
            next["PelletMaterial"] = String(recipe.material.dropFirst(7))
        } else {
            next["FilamentType"] = String(recipe.material.dropFirst(9))
        }
        fields = next
        materialAppearance = recipe.appearance
        dirty = true
    }
    func saveMaterialRecipe(_ recipe: MaterialRecipe) throws {
        var updated = savedMaterialRecipes.filter { $0.id != recipe.id }
        updated.append(recipe)
        let data = try JSONEncoder().encode(updated)
        preferences.set(data, forKey: MaterialRecipe.storageKey)
        savedMaterialRecipes = updated
        selectMaterialRecipe(recipe)
    }
}
