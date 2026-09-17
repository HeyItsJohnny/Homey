import SwiftUI

struct ChoreAssigneeOption: Identifiable, Hashable {
    let id: UUID
    let name: String
}

struct ChoreSingleAssigneePicker: View {
    let options: [ChoreAssigneeOption]
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    HStack {
                        Image(systemName: selection == option.id ? "checkmark.circle.fill" : "circle")
                        Text(option.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == option.id ? HomeyColors.primary : HomeyColors.text)
                .padding(.vertical, 5)
            }

            if selection == nil {
                Text("Select a person to assign this chore to.")
                    .font(.footnote)
                    .foregroundStyle(HomeyColors.danger)
            }
        }
    }
}

enum ChoreSingleAssigneeError: LocalizedError {
    case selectionRequired

    var errorDescription: String? { "Select a person to assign this chore to." }
}
