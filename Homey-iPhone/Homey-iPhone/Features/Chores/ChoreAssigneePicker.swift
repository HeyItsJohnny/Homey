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
                    ChoreAssigneePickerRow(option: option, isSelected: selection == option.id)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == option.id ? HomeyColors.primary : HomeyColors.text)
            }

            if selection == nil {
                Text("Select a person to assign this chore to.")
                    .font(.footnote)
                    .foregroundStyle(HomeyColors.danger)
            }
        }
    }
}

struct ChoreMultiAssigneePicker: View {
    let options: [ChoreAssigneeOption]
    @Binding var selection: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(options) { option in
                let isSelected = selection.contains(option.id)
                Button {
                    if isSelected { selection.remove(option.id) }
                    else { selection.insert(option.id) }
                } label: {
                    ChoreAssigneePickerRow(option: option, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? HomeyColors.primary : HomeyColors.text)
            }

            if selection.isEmpty {
                Text("Select at least one person to assign this task to.")
                    .font(.footnote)
                    .foregroundStyle(HomeyColors.danger)
            }
        }
    }
}

private struct ChoreAssigneePickerRow: View {
    let option: ChoreAssigneeOption
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            Text(option.name)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
    }
}

enum ChoreSingleAssigneeError: LocalizedError {
    case selectionRequired

    var errorDescription: String? { "Select a person to assign this chore to." }
}
