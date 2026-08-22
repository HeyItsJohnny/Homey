import SwiftUI

struct AddMealView: View {
    var onSaved: (UUID, Meal?, UUID?) -> Void = { _, _, _ in }

    var body: some View {
        MealEditorView(mode: .create, onSaved: onSaved)
    }
}
