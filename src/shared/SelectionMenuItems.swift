import SwiftUI

struct SelectionMenuItems: View {
    let options: [(String, String)]
    @Binding var selection: String

    var body: some View {
        ForEach(options, id: \.0) { value, title in
            Toggle(L(title), isOn: Binding(get: { selection == value }, set: { if $0 { selection = value } }))
        }
    }
}
